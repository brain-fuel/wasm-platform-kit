{-# LANGUAGE CPP #-}
#if !defined(wasm32_HOST_ARCH)
#error HostSDK.Canonical requires the wasm32 GHC backend
#endif
{-# LANGUAGE RecordWildCards #-}

-- | Memory32 canonical ABI support. Layouts come from upstream wit-parser.
-- Application modules never manipulate these pointers. ref:DEC-host-sdk-direct-haskell
module HostSDK.Canonical where

import Control.Exception (bracket, finally, onException)
import Control.Monad (forM, forM_, unless)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.State.Strict (StateT, get, put, runStateT)
import qualified Data.ByteString as B
import Data.IORef
import Data.Int
import Data.Text (Text)
import qualified Data.Text.Encoding as T
import Data.Word
import Foreign.Marshal.Alloc (free, mallocBytes)
import Foreign.Marshal.Utils (copyBytes, fillBytes)
import Foreign.Ptr
import Foreign.StablePtr
import Foreign.Storable
import System.IO.Unsafe (unsafePerformIO)
import System.Mem (performMajorGC)

-- | Identifies whether lifting transfers responsibility for the input allocation.
data Ownership = Borrowed | Owned deriving (Eq)

-- | Tracks allocations for one call or one exported result, including nested values.
newtype Arena = Arena (IORef [Ptr Word8])

-- | Consumes the flattened integer lanes selected by upstream canonical layout.
type Lift = StateT [Word64] IO

-- | Pairs a Haskell type with its canonical memory and flattened representations.
data Codec a = Codec
  { byteSize :: Int,
    laneCount :: Int,
    load :: Ownership -> Ptr Word8 -> IO a,
    store :: Arena -> Ptr Word8 -> a -> IO (),
    lower :: Arena -> a -> IO [Word64],
    liftValue :: Ownership -> Lift a
  }

-- | Starts an empty allocation scope before a call crosses the component boundary.
newArena :: IO Arena
newArena = Arena <$> newIORef []

-- | Frees every recorded allocation once, including on exceptional exits.
release :: Arena -> IO ()
release (Arena ref) = atomicModifyIORef' ref (\ps -> ([], ps)) >>= mapM_ free

-- | Brackets imported-call allocations so failed host operations also release them.
withArena :: (Arena -> IO a) -> IO a
withArena = bracket newArena release

-- | Records zeroed canonical storage in the current scope before exposing its address.
allocate :: Arena -> Int -> IO (Ptr Word8)
allocate (Arena ref) n = do
  unless (n >= 0) (fail "canonical allocation overflow")
  p <- mallocBytes (max 1 n)
  modifyIORef' ref (p :)
  fillBytes p 0 (max 1 n)
  pure p

-- | Converts a pointer to its memory32 lane; this module rejects other architectures.
address :: Ptr a -> Word32
address = fromIntegral . ptrToWordPtr

-- | Reconstructs a memory32 address supplied by the canonical ABI.
pointer :: Word32 -> Ptr Word8
pointer = wordPtrToPtr . fromIntegral

-- | Consumes one lane and rejects an incomplete flattened argument.
word :: Lift Word32
word = do
  xs <- get
  case xs of
    x : rest -> put rest >> pure (fromIntegral x)
    _ -> liftIO (fail "canonical ABI: missing lane")

-- | Decodes a complete generated value from its flattened lane payload.
runLift :: Codec a -> Ownership -> [Word64] -> IO a
runLift codec own values = fst <$> runStateT (liftValue codec own) values

-- | Isolates a variant payload so its decoder cannot consume the next argument.
lanes :: Int -> Lift [Word64]
lanes n = do
  xs <- get
  unless (length xs >= n) (liftIO (fail "canonical ABI: missing payload"))
  put (drop n xs)
  pure (take n xs)

-- | Fills unused variant lanes to the width chosen by the canonical ABI.
pad :: Int -> [Word64] -> [Word64]
pad n xs = take n (xs ++ repeat 0)

-- | Releases transferred input storage while retaining borrowed memory.
freeOwned :: Ownership -> Ptr a -> IO ()
freeOwned own p = if own == Owned then free p else pure ()

-- | Represents an absent result payload without allocating any lanes.
unitCodec :: Codec ()
unitCodec = Codec 0 0 (\_ _ -> pure ()) (\_ _ _ -> pure ()) (\_ _ -> pure []) (\_ -> pure ())

-- | Uses the ABI little-endian memory32 representation for unsigned words.
u32Codec :: Codec Word32
u32Codec = integralCodec 4

-- | Keeps byte storage distinct from its widened i32 call representation.
u8Codec :: Codec Word8
u8Codec = integralCodec 1

-- | Keeps a complete i64 lane without converting through a machine-sized Int.
wideWord :: Lift Word64
wideWord = do
  xs <- get
  case xs of
    x : rest -> put rest >> pure x
    _ -> liftIO (fail "canonical ABI: missing lane")

-- | Memory width and flattening width are distinct for small integer types.
integralCodec :: (Integral a, Storable a) => Int -> Codec a
integralCodec size =
  Codec
    size
    1
    (\_ p -> peek (castPtr p))
    (\_ p x -> poke (castPtr p) x)
    (\_ x -> pure [fromIntegral x])
    (\_ -> fromIntegral <$> wideWord)

u16Codec :: Codec Word16
u16Codec = integralCodec 2

u64Codec :: Codec Word64
u64Codec = integralCodec 8

s8Codec :: Codec Int8
s8Codec = integralCodec 1

s16Codec :: Codec Int16
s16Codec = integralCodec 2

s32Codec :: Codec Int32
s32Codec = integralCodec 4

s64Codec :: Codec Int64
s64Codec = integralCodec 8

-- | Maps canonical boolean bytes and lanes to Haskell Bool.
boolCodec :: Codec Bool
boolCodec = Codec 1 1 (\_ p -> (/= 0) <$> peek p) (\_ p x -> poke p (if x then 1 else 0)) (\_ x -> pure [if x then 1 else 0]) (\_ -> (/= 0) <$> word)

-- | Copies UTF-8 into Haskell ownership and rejects invalid text on lifting.
textCodec :: Codec Text
textCodec = Codec 8 2 readText writeText lowerText liftText
  where
    readText own p = do
      ptr <- peekByteOff p 0
      len <- peekByteOff p 4
      decode own ptr len
    decode own ptr len = do
      bytes <- B.packCStringLen (castPtr (pointer ptr), fromIntegral (len :: Word32))
      freeOwned own (pointer ptr)
      either (fail . show) pure (T.decodeUtf8' bytes)
    lowerText arena value = do
      let bytes = T.encodeUtf8 value
      p <- allocate arena (B.length bytes)
      B.useAsCStringLen bytes $ \(src, n) -> copyBytes p (castPtr src) n
      pure [fromIntegral (address p), fromIntegral (B.length bytes)]
    writeText arena p value = do
      values <- lowerText arena value
      case values of
        [ptr, len] -> pokeByteOff p 0 (fromIntegral ptr :: Word32) >> pokeByteOff p 4 (fromIntegral len :: Word32)
        _ -> fail "canonical text layout"
    liftText own = do
      ptr <- word
      len <- word
      liftIO (decode own ptr len)

-- | Uses upstream element stride and separately owns the array and nested values.
listCodec :: Codec a -> Codec [a]
listCodec item = Codec 8 2 readList writeList lowerList liftList
  where
    decode own ptr len = do
      let p = pointer ptr
      values <- forM [0 .. fromIntegral (len :: Word32) - 1] $ \i -> load item own (p `plusPtr` (i * byteSize item))
      freeOwned own p
      pure values
    readList own p = do
      ptr <- peekByteOff p 0
      len <- peekByteOff p 4
      decode own ptr len
    lowerList arena values = do
      let count = length values
      unless (toInteger count * toInteger (byteSize item) <= 2147483647) (fail "canonical list allocation overflow")
      p <- allocate arena (count * byteSize item)
      forM_ (zip [0 ..] values) $ \(i, value) -> store item arena (p `plusPtr` (i * byteSize item)) value
      pure [fromIntegral (address p), fromIntegral count]
    writeList arena p values = do
      raw <- lowerList arena values
      case raw of
        [ptr, len] -> pokeByteOff p 0 (fromIntegral ptr :: Word32) >> pokeByteOff p 4 (fromIntegral len :: Word32)
        _ -> fail "canonical list layout"
    liftList own = do
      ptr <- word
      len <- word
      liftIO (decode own ptr len)

-- | Retains only the outstanding exported result until canonical post-return runs.
{-# NOINLINE returned #-}
returned :: IORef (Maybe Arena)
returned = unsafePerformIO (newIORef Nothing)

-- | Keeps exported buffers alive through lifting and detects a missing post-return.
exportResult :: Codec a -> IO a -> IO Word32
exportResult codec action = do
  performMajorGC
  value <- action
  arena <- newArena
  ( do
      p <- allocate arena (byteSize codec)
      store codec arena p value
      old <- atomicModifyIORef' returned (\previous -> (Just arena, previous))
      case old of
        Nothing -> pure (address p)
        Just previous -> release previous >> fail "canonical ABI: missing post-return"
    )
    `onException` release arena

-- | Releases the outstanding result after the host has copied its canonical value.
postReturn :: Word32 -> IO ()
postReturn _ = do
  arena <- atomicModifyIORef' returned (\previous -> (Nothing, previous))
  maybe (pure ()) release arena

-- | Direct results have one scalar lane and no aggregate return allocation.
exportScalar :: (Integral b) => Codec a -> IO a -> IO b
exportScalar codec action = withArena $ \arena -> do
  value <- action
  raw <- lower codec arena value
  case raw of
    [lane] -> pure (fromIntegral lane)
    _ -> fail "canonical ABI: expected one result lane"

-- | An owned handle and a borrowed representation have distinct canonical meanings.
-- Constructors stay inside generated internals; applications use typed accessors.
data GuestResource a
  = GuestOwned Word32 (IORef Bool)
  | GuestBorrowed Word32 Integer
  deriving (Eq)

instance Show (GuestResource a) where
  show (GuestOwned _ _) = "<owned resource>"
  show (GuestBorrowed _ _) = "<borrowed resource>"

-- | Tracks dynamic borrow scopes without claiming Haskell has linear lifetimes.
{-# NOINLINE guestCall #-}
guestCall :: IORef (Integer, Maybe Integer)
guestCall = unsafePerformIO (newIORef (0, Nothing))

withGuestCall :: IO a -> IO a
withGuestCall action = bracket enter leave (const action)
  where
    enter = atomicModifyIORef' guestCall $ \(next, active) ->
      ((next + 1, Just next), active)
    leave previous = modifyIORef' guestCall (\(next, _) -> (next, previous))

ownedGuestResource :: Word32 -> IO (GuestResource a)
ownedGuestResource handle = GuestOwned handle <$> newIORef True

borrowedGuestResource :: Word32 -> IO (GuestResource a)
borrowedGuestResource rep = do
  (_, active) <- readIORef guestCall
  maybe (fail "canonical ABI: missing borrow scope") (pure . GuestBorrowed rep) active

-- | Retains typed application state until the component resource destructor runs.
newGuestResource :: (Word32 -> IO Word32) -> a -> IO (GuestResource a)
newGuestResource create value = do
  stable <- newStablePtr value
  (create (address (castStablePtrToPtr stable)) >>= ownedGuestResource)
    `onException` freeStablePtr stable

-- | Borrowed representations are usable only during the call that created them.
readGuestResource :: (Word32 -> IO Word32) -> GuestResource a -> IO a
readGuestResource rep resource = do
  raw <- case resource of
    GuestOwned _ _ -> guestHandle resource >>= rep
    GuestBorrowed value epoch -> do
      (_, active) <- readIORef guestCall
      unless (active == Just epoch) (fail "canonical ABI: expired resource borrow")
      pure value
  deRefStablePtr (castPtrToStablePtr (castPtr (pointer raw)))

-- | Runs application cleanup exactly at destruction, including cleanup exceptions.
destroyGuestResource :: (a -> IO ()) -> Word32 -> IO ()
destroyGuestResource destroy raw = do
  let stable = castPtrToStablePtr (castPtr (pointer raw))
  (deRefStablePtr stable >>= destroy) `finally` freeStablePtr stable

-- | Borrowed handles cannot be dropped or transferred as owned values.
guestHandle :: GuestResource a -> IO Word32
guestHandle (GuestOwned handle live) = do
  valid <- readIORef live
  unless valid (fail "canonical ABI: resource ownership already transferred")
  pure handle
guestHandle (GuestBorrowed _ _) = fail "canonical ABI: borrowed resource cannot escape its call"

-- | Invalidates aliases before an owned handle crosses the boundary or is dropped.
takeGuestHandle :: GuestResource a -> IO Word32
takeGuestHandle resource@(GuestOwned _ live) = do
  handle <- guestHandle resource
  writeIORef live False
  pure handle
takeGuestHandle (GuestBorrowed _ _) = fail "canonical ABI: borrowed resource cannot transfer ownership"

guestResourceCodec :: Bool -> Codec (GuestResource a)
guestResourceCodec borrowed =
  Codec
    4
    1
    (\own p -> load u32Codec own p >>= construct)
    (\arena p value -> lowerHandle value >>= store u32Codec arena p)
    (\arena value -> lowerHandle value >>= lower u32Codec arena)
    (\_ -> word >>= liftIO . construct)
  where
    construct = if borrowed then borrowedGuestResource else ownedGuestResource
    lowerHandle = if borrowed then guestHandle else takeGuestHandle

-- | Wraps an opaque resource without exposing its representation to application code.
mapCodec :: (a -> b) -> (b -> a) -> Codec a -> Codec b
mapCodec wrap unwrap codec =
  Codec
    (byteSize codec)
    (laneCount codec)
    (\own p -> wrap <$> load codec own p)
    (\arena p value -> store codec arena p (unwrap value))
    (\arena value -> lower codec arena (unwrap value))
    (\own -> wrap <$> liftValue codec own)

-- | Bulk binary values use ByteString rather than one heap object per octet.
bytesCodec :: Codec B.ByteString
bytesCodec = Codec 8 2 readBytes writeBytes lowerBytes liftBytes
  where
    decode own ptr len = do
      value <- B.packCStringLen (castPtr (pointer ptr), fromIntegral (len :: Word32))
      freeOwned own (pointer ptr)
      pure value
    readBytes own p = do
      ptr <- peekByteOff p 0
      len <- peekByteOff p 4
      decode own ptr len
    lowerBytes arena value = do
      p <- allocate arena (B.length value)
      B.useAsCStringLen value $ \(source, count) -> copyBytes p (castPtr source) count
      pure [fromIntegral (address p), fromIntegral (B.length value)]
    writeBytes arena p value = do
      raw <- lowerBytes arena value
      case raw of
        [ptr, len] -> pokeByteOff p 0 (fromIntegral ptr :: Word32) >> pokeByteOff p 4 (fromIntegral len :: Word32)
        _ -> fail "canonical byte buffer layout"
    liftBytes own = do
      ptr <- word
      len <- word
      liftIO (decode own ptr len)
