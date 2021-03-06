{-# LANGUAGE Haskell98, CPP, DeriveDataTypeable, ForeignFunctionInterface, TypeSynonymInstances #-}
{-# LINE 1 "dist/dist-sandbox-d76e0d17/build/Network/Socket/ByteString.hs" #-}













































{-# LINE 1 "Network/Socket/ByteString.hsc" #-}
{-# LANGUAGE CPP, ForeignFunctionInterface #-}
{-# LINE 2 "Network/Socket/ByteString.hsc" #-}


{-# LINE 4 "Network/Socket/ByteString.hsc" #-}

-- |
-- Module      : Network.Socket.ByteString
-- Copyright   : (c) Johan Tibell 2007-2010
-- License     : BSD-style
--
-- Maintainer  : johan.tibell@gmail.com
-- Stability   : stable
-- Portability : portable
--
-- This module provides access to the BSD /socket/ interface.  This
-- module is generally more efficient than the 'String' based network
-- functions in 'Network.Socket'.  For detailed documentation, consult
-- your favorite POSIX socket reference. All functions communicate
-- failures by converting the error number to 'System.IO.IOError'.
--
-- This module is made to be imported with 'Network.Socket' like so:
--
-- > import Network.Socket hiding (send, sendTo, recv, recvFrom)
-- > import Network.Socket.ByteString
--
module Network.Socket.ByteString
    (
    -- * Send data to a socket
      send
    , sendAll
    , sendTo
    , sendAllTo

    -- ** Vectored I/O
    -- $vectored
    , sendMany
    , sendManyTo

    -- * Receive data from a socket
    , recv
    , recvFrom

    -- * Example
    -- $example
    ) where

import Control.Monad (liftM, when)
import Data.ByteString (ByteString)
import Data.ByteString.Internal (createAndTrim)
import Data.ByteString.Unsafe (unsafeUseAsCStringLen)
import Data.Word (Word8)
import Foreign.C.Types (CInt(..))
import Foreign.Marshal.Alloc (allocaBytes)
import Foreign.Ptr (Ptr, castPtr)
import Network.Socket (SockAddr, Socket(..), sendBufTo, recvBufFrom)

import qualified Data.ByteString as B

import Network.Socket.ByteString.Internal
import Network.Socket.Internal
import Network.Socket.Types


{-# LINE 63 "Network/Socket/ByteString.hsc" #-}
import Control.Monad (zipWithM_)
import Foreign.C.Types (CChar)
import Foreign.C.Types (CSize(..))
import Foreign.Marshal.Array (allocaArray)
import Foreign.Marshal.Utils (with)
import Foreign.Ptr (plusPtr)
import Foreign.Storable (Storable(..))

import Network.Socket.ByteString.IOVec (IOVec(..))
import Network.Socket.ByteString.MsgHdr (MsgHdr(..))


{-# LINE 77 "Network/Socket/ByteString.hsc" #-}


{-# LINE 79 "Network/Socket/ByteString.hsc" #-}
foreign import ccall unsafe "send"
  c_send :: CInt -> Ptr a -> CSize -> CInt -> IO CInt
foreign import ccall unsafe "recv"
  c_recv :: CInt -> Ptr CChar -> CSize -> CInt -> IO CInt

{-# LINE 84 "Network/Socket/ByteString.hsc" #-}

-- ----------------------------------------------------------------------------
-- Sending

-- | Send data to the socket.  The socket must be connected to a
-- remote socket.  Returns the number of bytes sent. Applications are
-- responsible for ensuring that all data has been sent.
send :: Socket      -- ^ Connected socket
     -> ByteString  -- ^ Data to send
     -> IO Int      -- ^ Number of bytes sent
send sock@(MkSocket s _ _ _ _) xs =
    unsafeUseAsCStringLen xs $ \(str, len) ->
    liftM fromIntegral $

{-# LINE 101 "Network/Socket/ByteString.hsc" #-}
        throwSocketErrorWaitWrite sock "send" $
        c_send s str (fromIntegral len) 0

{-# LINE 104 "Network/Socket/ByteString.hsc" #-}

-- | Send data to the socket.  The socket must be connected to a
-- remote socket.  Unlike 'send', this function continues to send data
-- until either all data has been sent or an error occurs.  On error,
-- an exception is raised, and there is no way to determine how much
-- data, if any, was successfully sent.
sendAll :: Socket      -- ^ Connected socket
        -> ByteString  -- ^ Data to send
        -> IO ()
sendAll sock bs = do
    sent <- send sock bs
    when (sent < B.length bs) $ sendAll sock (B.drop sent bs)

-- | Send data to the socket.  The recipient can be specified
-- explicitly, so the socket need not be in a connected state.
-- Returns the number of bytes sent. Applications are responsible for
-- ensuring that all data has been sent.
sendTo :: Socket      -- ^ Socket
       -> ByteString  -- ^ Data to send
       -> SockAddr    -- ^ Recipient address
       -> IO Int      -- ^ Number of bytes sent
sendTo sock xs addr =
    unsafeUseAsCStringLen xs $ \(str, len) -> sendBufTo sock str len addr

-- | Send data to the socket. The recipient can be specified
-- explicitly, so the socket need not be in a connected state.  Unlike
-- 'sendTo', this function continues to send data until either all
-- data has been sent or an error occurs.  On error, an exception is
-- raised, and there is no way to determine how much data, if any, was
-- successfully sent.
sendAllTo :: Socket      -- ^ Socket
          -> ByteString  -- ^ Data to send
          -> SockAddr    -- ^ Recipient address
          -> IO ()
sendAllTo sock xs addr = do
    sent <- sendTo sock xs addr
    when (sent < B.length xs) $ sendAllTo sock (B.drop sent xs) addr

-- ----------------------------------------------------------------------------
-- ** Vectored I/O

-- $vectored
--
-- Vectored I\/O, also known as scatter\/gather I\/O, allows multiple
-- data segments to be sent using a single system call, without first
-- concatenating the segments.  For example, given a list of
-- @ByteString@s, @xs@,
--
-- > sendMany sock xs
--
-- is equivalent to
--
-- > sendAll sock (concat xs)
--
-- but potentially more efficient.
--
-- Vectored I\/O are often useful when implementing network protocols
-- that, for example, group data into segments consisting of one or
-- more fixed-length headers followed by a variable-length body.

-- | Send data to the socket.  The socket must be in a connected
-- state.  The data is sent as if the parts have been concatenated.
-- This function continues to send data until either all data has been
-- sent or an error occurs.  On error, an exception is raised, and
-- there is no way to determine how much data, if any, was
-- successfully sent.
sendMany :: Socket        -- ^ Connected socket
         -> [ByteString]  -- ^ Data to send
         -> IO ()

{-# LINE 174 "Network/Socket/ByteString.hsc" #-}
sendMany sock@(MkSocket fd _ _ _ _) cs = do
    sent <- sendManyInner
    when (sent < totalLength cs) $ sendMany sock (remainingChunks sent cs)
  where
    sendManyInner =
      liftM fromIntegral . withIOVec cs $ \(iovsPtr, iovsLen) ->
          throwSocketErrorWaitWrite sock "writev" $
              c_writev (fromIntegral fd) iovsPtr
              (fromIntegral (min iovsLen (1024)))
{-# LINE 183 "Network/Socket/ByteString.hsc" #-}

{-# LINE 186 "Network/Socket/ByteString.hsc" #-}

-- | Send data to the socket.  The recipient can be specified
-- explicitly, so the socket need not be in a connected state.  The
-- data is sent as if the parts have been concatenated.  This function
-- continues to send data until either all data has been sent or an
-- error occurs.  On error, an exception is raised, and there is no
-- way to determine how much data, if any, was successfully sent.
sendManyTo :: Socket        -- ^ Socket
           -> [ByteString]  -- ^ Data to send
           -> SockAddr      -- ^ Recipient address
           -> IO ()

{-# LINE 198 "Network/Socket/ByteString.hsc" #-}
sendManyTo sock@(MkSocket fd _ _ _ _) cs addr = do
    sent <- liftM fromIntegral sendManyToInner
    when (sent < totalLength cs) $ sendManyTo sock (remainingChunks sent cs) addr
  where
    sendManyToInner =
      withSockAddr addr $ \addrPtr addrSize ->
        withIOVec cs $ \(iovsPtr, iovsLen) -> do
          let msgHdr = MsgHdr
                addrPtr (fromIntegral addrSize)
                iovsPtr (fromIntegral iovsLen)
          with msgHdr $ \msgHdrPtr ->
            throwSocketErrorWaitWrite sock "sendmsg" $
              c_sendmsg (fromIntegral fd) msgHdrPtr 0

{-# LINE 214 "Network/Socket/ByteString.hsc" #-}

-- ----------------------------------------------------------------------------
-- Receiving

-- | Receive data from the socket.  The socket must be in a connected
-- state.  This function may return fewer bytes than specified.  If
-- the message is longer than the specified length, it may be
-- discarded depending on the type of socket.  This function may block
-- until a message arrives.
--
-- Considering hardware and network realities, the maximum number of bytes to
-- receive should be a small power of 2, e.g., 4096.
--
-- For TCP sockets, a zero length return value means the peer has
-- closed its half side of the connection.
recv :: Socket         -- ^ Connected socket
     -> Int            -- ^ Maximum number of bytes to receive
     -> IO ByteString  -- ^ Data received
recv sock nbytes
    | nbytes < 0 = ioError (mkInvalidRecvArgError "Network.Socket.ByteString.recv")
    | otherwise  = createAndTrim nbytes $ recvInner sock nbytes

recvInner :: Socket -> Int -> Ptr Word8 -> IO Int
recvInner sock nbytes ptr =
    fmap fromIntegral $

{-# LINE 242 "Network/Socket/ByteString.hsc" #-}
        throwSocketErrorWaitRead sock "recv" $
        c_recv s (castPtr ptr) (fromIntegral nbytes) 0

{-# LINE 245 "Network/Socket/ByteString.hsc" #-}
  where
    s = sockFd sock

-- | Receive data from the socket.  The socket need not be in a
-- connected state.  Returns @(bytes, address)@ where @bytes@ is a
-- 'ByteString' representing the data received and @address@ is a
-- 'SockAddr' representing the address of the sending socket.
recvFrom :: Socket                     -- ^ Socket
         -> Int                        -- ^ Maximum number of bytes to receive
         -> IO (ByteString, SockAddr)  -- ^ Data received and sender address
recvFrom sock nbytes =
    allocaBytes nbytes $ \ptr -> do
        (len, sockaddr) <- recvBufFrom sock ptr nbytes
        str <- B.packCStringLen (ptr, len)
        return (str, sockaddr)

-- ----------------------------------------------------------------------------
-- Not exported


{-# LINE 265 "Network/Socket/ByteString.hsc" #-}
-- | Suppose we try to transmit a list of chunks @cs@ via a gathering write
-- operation and find that @n@ bytes were sent. Then @remainingChunks n cs@ is
-- list of chunks remaining to be sent.
remainingChunks :: Int -> [ByteString] -> [ByteString]
remainingChunks _ [] = []
remainingChunks i (x:xs)
    | i < len        = B.drop i x : xs
    | otherwise      = let i' = i - len in i' `seq` remainingChunks i' xs
  where
    len = B.length x

-- | @totalLength cs@ is the sum of the lengths of the chunks in the list @cs@.
totalLength :: [ByteString] -> Int
totalLength = sum . map B.length

-- | @withIOVec cs f@ executes the computation @f@, passing as argument a pair
-- consisting of a pointer to a temporarily allocated array of pointers to
-- 'IOVec' made from @cs@ and the number of pointers (@length cs@).
-- /Unix only/.
withIOVec :: [ByteString] -> ((Ptr IOVec, Int) -> IO a) -> IO a
withIOVec cs f =
    allocaArray csLen $ \aPtr -> do
        zipWithM_ pokeIov (ptrs aPtr) cs
        f (aPtr, csLen)
  where
    csLen = length cs
    ptrs = iterate (`plusPtr` sizeOf (undefined :: IOVec))
    pokeIov ptr s =
        unsafeUseAsCStringLen s $ \(sPtr, sLen) ->
        poke ptr $ IOVec sPtr (fromIntegral sLen)

{-# LINE 296 "Network/Socket/ByteString.hsc" #-}

-- ---------------------------------------------------------------------
-- Example

-- $example
--
-- Here are two minimal example programs using the TCP/IP protocol: a
-- server that echoes all data that it receives back (servicing only
-- one client) and a client using it.
--
-- > -- Echo server program
-- > module Main where
-- >
-- > import Control.Monad (unless)
-- > import Network.Socket hiding (recv)
-- > import qualified Data.ByteString as S
-- > import Network.Socket.ByteString (recv, sendAll)
-- >
-- > main :: IO ()
-- > main = withSocketsDo $
-- >     do addrinfos <- getAddrInfo
-- >                     (Just (defaultHints {addrFlags = [AI_PASSIVE]}))
-- >                     Nothing (Just "3000")
-- >        let serveraddr = head addrinfos
-- >        sock <- socket (addrFamily serveraddr) Stream defaultProtocol
-- >        bindSocket sock (addrAddress serveraddr)
-- >        listen sock 1
-- >        (conn, _) <- accept sock
-- >        talk conn
-- >        sClose conn
-- >        sClose sock
-- >
-- >     where
-- >       talk :: Socket -> IO ()
-- >       talk conn =
-- >           do msg <- recv conn 1024
-- >              unless (S.null msg) $ sendAll conn msg >> talk conn
--
-- > -- Echo client program
-- > module Main where
-- >
-- > import Network.Socket hiding (recv)
-- > import Network.Socket.ByteString (recv, sendAll)
-- > import qualified Data.ByteString.Char8 as C
-- >
-- > main :: IO ()
-- > main = withSocketsDo $
-- >     do addrinfos <- getAddrInfo Nothing (Just "") (Just "3000")
-- >        let serveraddr = head addrinfos
-- >        sock <- socket (addrFamily serveraddr) Stream defaultProtocol
-- >        connect sock (addrAddress serveraddr)
-- >        sendAll sock $ C.pack "Hello, world!"
-- >        msg <- recv sock 1024
-- >        sClose sock
-- >        putStr "Received "
-- >        C.putStrLn msg
