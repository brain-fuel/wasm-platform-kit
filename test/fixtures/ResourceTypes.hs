-- | Typed resource state lives with the consuming application, not the SDK.
module ResourceTypes where

import Data.IORef
import Data.Text (Text)
import System.IO.Unsafe (unsafePerformIO)

type ApplicationSnapshot = [Text]

{-# NOINLINE destructions #-}
destructions :: IORef Int
destructions = unsafePerformIO (newIORef 0)

destroyApplicationSnapshot :: ApplicationSnapshot -> IO ()
destroyApplicationSnapshot _ = modifyIORef' destructions (+ 1)
