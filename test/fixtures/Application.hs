{-# LANGUAGE OverloadedStrings #-}

-- | Independent ABI conformance fixture. ref:DEC-host-sdk-direct-haskell
module Application (reject, snapshotFromOne, remember, rememberedSize, answer, replyValue, large, roundTrip, echo, exercise, scalars, scalar, nothing, snapshotNew, snapshotRead, snapshotSize, consume, destroyed) where

import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Word (Word32, Word64)
import Host
import qualified ResourceTypes
import System.IO.Unsafe (unsafePerformIO)

-- | Round-trips nested records and lists through the generated ABI.
roundTrip :: ApplicationPayload -> IO (Either HostError ApplicationPayload)
roundTrip = pure . Right

-- | Exercises both ordinary Unicode returns and an exception escaping the guest.
echo :: Text -> IO (Either HostError Text)
echo "__panic" = ioError (userError "deliberate Haskell exception")
echo value = pure (Right value)

-- | Exercises acquired resource cleanup across repeated host calls.
exercise :: Text -> HostRequest -> IO (Either HostError Text)
exercise name request = do
  granted <- acquire name
  case granted of
    Left err -> pure (Left err)
    Right provider -> withHostProvider (pure provider) (\handle -> perform handle request)

-- | Covers memory widths, i64 lanes, variant joins and bulk byte transport.
scalars :: ApplicationScalarPayload -> IO (Either HostError ApplicationScalarPayload)
scalars = pure . Right

scalar :: Word64 -> IO Word64
scalar = pure

nothing :: IO ()
nothing = pure ()

-- | Snapshot readers bulk-copy a bounded slice; the table stays in the guest.
snapshotNew :: [Text] -> IO ApplicationSnapshot
snapshotNew = newApplicationSnapshot

snapshotRead :: ApplicationSnapshot -> Word32 -> Word32 -> IO [Text]
snapshotRead resource start count = do
  values <- readApplicationSnapshot resource
  pure (take (fromIntegral count) (drop (fromIntegral start) values))

snapshotSize :: ApplicationSnapshot -> IO Word32
snapshotSize resource = fromIntegral . length <$> readApplicationSnapshot resource

consume :: ApplicationSnapshot -> IO Word32
consume resource = withApplicationSnapshot (pure resource) snapshotSize

destroyed :: IO Word32
destroyed = fromIntegral <$> readIORef ResourceTypes.destructions

-- | This request exceeds the canonical flat-parameter limit and uses indirect storage.
large :: ApplicationLargeRequest -> IO (Either HostError ApplicationLargeRequest)
large = pure . Right

answer :: Word64 -> IO (Either HostError Word64)
answer = pure . Right

replyValue :: ApplicationReply -> IO ApplicationReply
replyValue = pure

-- | Deliberately retain a borrowed wrapper to exercise dynamic expiry checks.
{-# NOINLINE remembered #-}
remembered :: IORef (Maybe ApplicationSnapshot)
remembered = unsafePerformIO (newIORef Nothing)

remember :: ApplicationSnapshot -> IO ()
remember resource = writeIORef remembered (Just resource)

rememberedSize :: IO Word32
rememberedSize = readIORef remembered >>= maybe (pure 0) snapshotSize

-- | Ordinary result errors preserve their typed payload and do not trap the store.
reject :: Text -> IO (Either Text ())
reject = pure . Left

snapshotFromOne :: Text -> IO ApplicationSnapshot
snapshotFromOne value = newApplicationSnapshot [value]
