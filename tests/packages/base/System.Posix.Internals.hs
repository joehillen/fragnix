{-# LANGUAGE Haskell2010 #-}
{-# LINE 1 "System/Posix/Internals.hs" #-}













































{-# LANGUAGE Trustworthy #-}
{-# LANGUAGE CPP, NoImplicitPrelude, CApiFFI #-}
{-# OPTIONS_HADDOCK hide #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  System.Posix.Internals
-- Copyright   :  (c) The University of Glasgow, 1992-2002
-- License     :  see libraries/base/LICENSE
-- 
-- Maintainer  :  cvs-ghc@haskell.org
-- Stability   :  internal
-- Portability :  non-portable (requires POSIX)
--
-- POSIX support layer for the standard libraries.
-- This library is built on *every* platform, including Win32.
--
-- Non-posix compliant in order to support the following features:
--      * S_ISSOCK (no sockets in POSIX)
--
-----------------------------------------------------------------------------

module System.Posix.Internals where

















































































































































































































































































































































































































































import Control.Monad
import System.Posix.Types

import Foreign
import Foreign.C

-- import Data.Bits
import Data.Maybe


import GHC.Base
import GHC.Num
import GHC.Real
import GHC.IO
import GHC.IO.IOMode
import GHC.IO.Exception
import GHC.IO.Device
import {-# SOURCE #-} GHC.IO.Encoding (getFileSystemEncoding)
import qualified GHC.Foreign as GHC

-- ---------------------------------------------------------------------------
-- Debugging the base package

puts :: String -> IO ()
puts s = withCAStringLen (s ++ "\n") $ \(p, len) -> do
            -- In reality should be withCString, but assume ASCII to avoid loop
            -- if this is called by GHC.Foreign
           _ <- c_write 1 (castPtr p) (fromIntegral len)
           return ()


-- ---------------------------------------------------------------------------
-- Types

type CFLock     = ()
type CGroup     = ()
type CLconv     = ()
type CPasswd    = ()
type CSigaction = ()
data {-# CTYPE "sigset_t" #-} CSigset
type CStat      = ()
type CTermios   = ()
type CTm        = ()
type CTms       = ()
type CUtimbuf   = ()
type CUtsname   = ()

type FD = CInt

-- ---------------------------------------------------------------------------
-- stat()-related stuff

fdFileSize :: FD -> IO Integer
fdFileSize fd = 
  allocaBytes sizeof_stat $ \ p_stat -> do
    throwErrnoIfMinus1Retry_ "fileSize" $
        c_fstat fd p_stat
    c_mode <- st_mode p_stat :: IO CMode 
    if not (s_isreg c_mode)
        then return (-1)
        else do
      c_size <- st_size p_stat
      return (fromIntegral c_size)

fileType :: FilePath -> IO IODeviceType
fileType file =
  allocaBytes sizeof_stat $ \ p_stat -> do
  withFilePath file $ \p_file -> do
    throwErrnoIfMinus1Retry_ "fileType" $
      c_stat p_file p_stat
    statGetType p_stat

-- NOTE: On Win32 platforms, this will only work with file descriptors
-- referring to file handles. i.e., it'll fail for socket FDs.
fdStat :: FD -> IO (IODeviceType, CDev, CIno)
fdStat fd = 
  allocaBytes sizeof_stat $ \ p_stat -> do
    throwErrnoIfMinus1Retry_ "fdType" $
        c_fstat fd p_stat
    ty <- statGetType p_stat
    dev <- st_dev p_stat
    ino <- st_ino p_stat
    return (ty,dev,ino)
    
fdType :: FD -> IO IODeviceType
fdType fd = do (ty,_,_) <- fdStat fd; return ty

statGetType :: Ptr CStat -> IO IODeviceType
statGetType p_stat = do
  c_mode <- st_mode p_stat :: IO CMode
  case () of
      _ | s_isdir c_mode        -> return Directory
        | s_isfifo c_mode || s_issock c_mode || s_ischr  c_mode
                                -> return Stream
        | s_isreg c_mode        -> return RegularFile
         -- Q: map char devices to RawDevice too?
        | s_isblk c_mode        -> return RawDevice
        | otherwise             -> ioError ioe_unknownfiletype
    
ioe_unknownfiletype :: IOException
ioe_unknownfiletype = IOError Nothing UnsupportedOperation "fdType"
                        "unknown file type"
                        Nothing
                        Nothing

fdGetMode :: FD -> IO IOMode
fdGetMode fd = do
    flags <- throwErrnoIfMinus1Retry "fdGetMode" 
                (c_fcntl_read fd const_f_getfl)
    let
       wH  = (flags .&. o_WRONLY) /= 0
       aH  = (flags .&. o_APPEND) /= 0
       rwH = (flags .&. o_RDWR) /= 0

       mode
         | wH && aH  = AppendMode
         | wH        = WriteMode
         | rwH       = ReadWriteMode
         | otherwise = ReadMode
          
    return mode


withFilePath :: FilePath -> (CString -> IO a) -> IO a
newFilePath :: FilePath -> IO CString
peekFilePath :: CString -> IO FilePath
peekFilePathLen :: CStringLen -> IO FilePath

withFilePath fp f = getFileSystemEncoding >>= \enc -> GHC.withCString enc fp f
newFilePath fp = getFileSystemEncoding >>= \enc -> GHC.newCString enc fp
peekFilePath fp = getFileSystemEncoding >>= \enc -> GHC.peekCString enc fp
peekFilePathLen fp = getFileSystemEncoding >>= \enc -> GHC.peekCStringLen enc fp


-- ---------------------------------------------------------------------------
-- Terminal-related stuff


setEcho :: FD -> Bool -> IO ()
setEcho fd on = do
  tcSetAttr fd $ \ p_tios -> do
    lflag <- c_lflag p_tios :: IO CTcflag
    let new_lflag
         | on        = lflag .|. fromIntegral const_echo
         | otherwise = lflag .&. complement (fromIntegral const_echo)
    poke_c_lflag p_tios (new_lflag :: CTcflag)

getEcho :: FD -> IO Bool
getEcho fd = do
  tcSetAttr fd $ \ p_tios -> do
    lflag <- c_lflag p_tios :: IO CTcflag
    return ((lflag .&. fromIntegral const_echo) /= 0)

setCooked :: FD -> Bool -> IO ()
setCooked fd cooked = 
  tcSetAttr fd $ \ p_tios -> do

    -- turn on/off ICANON
    lflag <- c_lflag p_tios :: IO CTcflag
    let new_lflag | cooked    = lflag .|. (fromIntegral const_icanon)
                  | otherwise = lflag .&. complement (fromIntegral const_icanon)
    poke_c_lflag p_tios (new_lflag :: CTcflag)

    -- set VMIN & VTIME to 1/0 respectively
    when (not cooked) $ do
            c_cc <- ptr_c_cc p_tios
            let vmin  = (c_cc `plusPtr` (fromIntegral const_vmin))  :: Ptr Word8
                vtime = (c_cc `plusPtr` (fromIntegral const_vtime)) :: Ptr Word8
            poke vmin  1
            poke vtime 0

tcSetAttr :: FD -> (Ptr CTermios -> IO a) -> IO a
tcSetAttr fd fun = do
     allocaBytes sizeof_termios  $ \p_tios -> do
        throwErrnoIfMinus1Retry_ "tcSetAttr"
           (c_tcgetattr fd p_tios)

        -- Save a copy of termios, if this is a standard file descriptor.
        -- These terminal settings are restored in hs_exit().
        when (fd <= 2) $ do
          p <- get_saved_termios fd
          when (p == nullPtr) $ do
             saved_tios <- mallocBytes sizeof_termios
             copyBytes saved_tios p_tios sizeof_termios
             set_saved_termios fd saved_tios

        -- tcsetattr() when invoked by a background process causes the process
        -- to be sent SIGTTOU regardless of whether the process has TOSTOP set
        -- in its terminal flags (try it...).  This function provides a
        -- wrapper which temporarily blocks SIGTTOU around the call, making it
        -- transparent.
        allocaBytes sizeof_sigset_t $ \ p_sigset -> do
          allocaBytes sizeof_sigset_t $ \ p_old_sigset -> do
             throwErrnoIfMinus1_ "sigemptyset" $
                 c_sigemptyset p_sigset
             throwErrnoIfMinus1_ "sigaddset" $
                 c_sigaddset   p_sigset const_sigttou
             throwErrnoIfMinus1_ "sigprocmask" $
                 c_sigprocmask const_sig_block p_sigset p_old_sigset
             r <- fun p_tios  -- do the business
             throwErrnoIfMinus1Retry_ "tcSetAttr" $
                 c_tcsetattr fd const_tcsanow p_tios
             throwErrnoIfMinus1_ "sigprocmask" $
                 c_sigprocmask const_sig_setmask p_old_sigset nullPtr
             return r

foreign import ccall unsafe "HsBase.h __hscore_get_saved_termios"
   get_saved_termios :: CInt -> IO (Ptr CTermios)

foreign import ccall unsafe "HsBase.h __hscore_set_saved_termios"
   set_saved_termios :: CInt -> (Ptr CTermios) -> IO ()


-- ---------------------------------------------------------------------------
-- Turning on non-blocking for a file descriptor

setNonBlockingFD :: FD -> Bool -> IO ()
setNonBlockingFD fd set = do
  flags <- throwErrnoIfMinus1Retry "setNonBlockingFD"
                 (c_fcntl_read fd const_f_getfl)
  let flags' | set       = flags .|. o_NONBLOCK
             | otherwise = flags .&. complement o_NONBLOCK
  unless (flags == flags') $ do
    -- An error when setting O_NONBLOCK isn't fatal: on some systems
    -- there are certain file handles on which this will fail (eg. /dev/null
    -- on FreeBSD) so we throw away the return code from fcntl_write.
    _ <- c_fcntl_write fd const_f_setfl (fromIntegral flags')
    return ()

-- -----------------------------------------------------------------------------
-- Set close-on-exec for a file descriptor

setCloseOnExec :: FD -> IO ()
setCloseOnExec fd = do
  throwErrnoIfMinus1_ "setCloseOnExec" $
    c_fcntl_write fd const_f_setfd const_fd_cloexec

-- -----------------------------------------------------------------------------
-- foreign imports

type CFilePath = CString

foreign import ccall unsafe "HsBase.h access"
   c_access :: CString -> CInt -> IO CInt

foreign import ccall unsafe "HsBase.h chmod"
   c_chmod :: CString -> CMode -> IO CInt

foreign import ccall unsafe "HsBase.h close"
   c_close :: CInt -> IO CInt

foreign import ccall unsafe "HsBase.h creat"
   c_creat :: CString -> CMode -> IO CInt

foreign import ccall unsafe "HsBase.h dup"
   c_dup :: CInt -> IO CInt

foreign import ccall unsafe "HsBase.h dup2"
   c_dup2 :: CInt -> CInt -> IO CInt

foreign import ccall unsafe "HsBase.h __hscore_fstat"
   c_fstat :: CInt -> Ptr CStat -> IO CInt

foreign import ccall unsafe "HsBase.h isatty"
   c_isatty :: CInt -> IO CInt

-- We use CAPI as on some OSs (eg. Linux) this is wrapped by a macro
-- which redirects to the 64-bit-off_t versions when large file
-- support is enabled.
foreign import capi unsafe "unistd.h lseek"
   c_lseek :: CInt -> COff -> CInt -> IO COff

foreign import ccall unsafe "HsBase.h __hscore_lstat"
   lstat :: CFilePath -> Ptr CStat -> IO CInt

foreign import ccall unsafe "HsBase.h __hscore_open"
   c_open :: CFilePath -> CInt -> CMode -> IO CInt

foreign import ccall safe "HsBase.h __hscore_open"
   c_safe_open :: CFilePath -> CInt -> CMode -> IO CInt

-- See Note: CSsize
foreign import capi unsafe "HsBase.h read"
   c_read :: CInt -> Ptr Word8 -> CSize -> IO CSsize

-- See Note: CSsize
foreign import capi safe "HsBase.h read"
   c_safe_read :: CInt -> Ptr Word8 -> CSize -> IO CSsize

foreign import ccall unsafe "HsBase.h __hscore_stat"
   c_stat :: CFilePath -> Ptr CStat -> IO CInt

foreign import ccall unsafe "HsBase.h umask"
   c_umask :: CMode -> IO CMode

-- See Note: CSsize
foreign import capi unsafe "HsBase.h write"
   c_write :: CInt -> Ptr Word8 -> CSize -> IO CSsize

-- See Note: CSsize
foreign import capi safe "HsBase.h write"
   c_safe_write :: CInt -> Ptr Word8 -> CSize -> IO CSsize

foreign import ccall unsafe "HsBase.h __hscore_ftruncate"
   c_ftruncate :: CInt -> COff -> IO CInt

foreign import ccall unsafe "HsBase.h unlink"
   c_unlink :: CString -> IO CInt

foreign import ccall unsafe "HsBase.h getpid"
   c_getpid :: IO CPid

foreign import capi unsafe "HsBase.h fcntl"
   c_fcntl_read  :: CInt -> CInt -> IO CInt

foreign import capi unsafe "HsBase.h fcntl"
   c_fcntl_write :: CInt -> CInt -> CLong -> IO CInt

foreign import capi unsafe "HsBase.h fcntl"
   c_fcntl_lock  :: CInt -> CInt -> Ptr CFLock -> IO CInt

foreign import ccall unsafe "HsBase.h fork"
   c_fork :: IO CPid 

foreign import ccall unsafe "HsBase.h link"
   c_link :: CString -> CString -> IO CInt

-- capi is required at least on Android
foreign import capi unsafe "HsBase.h mkfifo"
   c_mkfifo :: CString -> CMode -> IO CInt

foreign import ccall unsafe "HsBase.h pipe"
   c_pipe :: Ptr CInt -> IO CInt

foreign import capi unsafe "signal.h sigemptyset"
   c_sigemptyset :: Ptr CSigset -> IO CInt

foreign import capi unsafe "signal.h sigaddset"
   c_sigaddset :: Ptr CSigset -> CInt -> IO CInt

foreign import capi unsafe "signal.h sigprocmask"
   c_sigprocmask :: CInt -> Ptr CSigset -> Ptr CSigset -> IO CInt

-- capi is required at least on Android
foreign import capi unsafe "HsBase.h tcgetattr"
   c_tcgetattr :: CInt -> Ptr CTermios -> IO CInt

-- capi is required at least on Android
foreign import capi unsafe "HsBase.h tcsetattr"
   c_tcsetattr :: CInt -> CInt -> Ptr CTermios -> IO CInt

foreign import capi unsafe "HsBase.h utime"
   c_utime :: CString -> Ptr CUtimbuf -> IO CInt

foreign import ccall unsafe "HsBase.h waitpid"
   c_waitpid :: CPid -> Ptr CInt -> CInt -> IO CPid

-- POSIX flags only:
foreign import ccall unsafe "HsBase.h __hscore_o_rdonly" o_RDONLY :: CInt
foreign import ccall unsafe "HsBase.h __hscore_o_wronly" o_WRONLY :: CInt
foreign import ccall unsafe "HsBase.h __hscore_o_rdwr"   o_RDWR   :: CInt
foreign import ccall unsafe "HsBase.h __hscore_o_append" o_APPEND :: CInt
foreign import ccall unsafe "HsBase.h __hscore_o_creat"  o_CREAT  :: CInt
foreign import ccall unsafe "HsBase.h __hscore_o_excl"   o_EXCL   :: CInt
foreign import ccall unsafe "HsBase.h __hscore_o_trunc"  o_TRUNC  :: CInt

-- non-POSIX flags.
foreign import ccall unsafe "HsBase.h __hscore_o_noctty"   o_NOCTTY   :: CInt
foreign import ccall unsafe "HsBase.h __hscore_o_nonblock" o_NONBLOCK :: CInt
foreign import ccall unsafe "HsBase.h __hscore_o_binary"   o_BINARY   :: CInt

foreign import capi unsafe "sys/stat.h S_ISREG"  c_s_isreg  :: CMode -> CInt
foreign import capi unsafe "sys/stat.h S_ISCHR"  c_s_ischr  :: CMode -> CInt
foreign import capi unsafe "sys/stat.h S_ISBLK"  c_s_isblk  :: CMode -> CInt
foreign import capi unsafe "sys/stat.h S_ISDIR"  c_s_isdir  :: CMode -> CInt
foreign import capi unsafe "sys/stat.h S_ISFIFO" c_s_isfifo :: CMode -> CInt

s_isreg  :: CMode -> Bool
s_isreg cm = c_s_isreg cm /= 0
s_ischr  :: CMode -> Bool
s_ischr cm = c_s_ischr cm /= 0
s_isblk  :: CMode -> Bool
s_isblk cm = c_s_isblk cm /= 0
s_isdir  :: CMode -> Bool
s_isdir cm = c_s_isdir cm /= 0
s_isfifo :: CMode -> Bool
s_isfifo cm = c_s_isfifo cm /= 0

foreign import ccall unsafe "HsBase.h __hscore_sizeof_stat" sizeof_stat :: Int
foreign import ccall unsafe "HsBase.h __hscore_st_mtime" st_mtime :: Ptr CStat -> IO CTime
foreign import ccall unsafe "HsBase.h __hscore_st_size" st_size :: Ptr CStat -> IO COff
foreign import ccall unsafe "HsBase.h __hscore_st_mode" st_mode :: Ptr CStat -> IO CMode
foreign import ccall unsafe "HsBase.h __hscore_st_dev" st_dev :: Ptr CStat -> IO CDev
foreign import ccall unsafe "HsBase.h __hscore_st_ino" st_ino :: Ptr CStat -> IO CIno

foreign import ccall unsafe "HsBase.h __hscore_echo"         const_echo :: CInt
foreign import ccall unsafe "HsBase.h __hscore_tcsanow"      const_tcsanow :: CInt
foreign import ccall unsafe "HsBase.h __hscore_icanon"       const_icanon :: CInt
foreign import ccall unsafe "HsBase.h __hscore_vmin"         const_vmin   :: CInt
foreign import ccall unsafe "HsBase.h __hscore_vtime"        const_vtime  :: CInt
foreign import ccall unsafe "HsBase.h __hscore_sigttou"      const_sigttou :: CInt
foreign import ccall unsafe "HsBase.h __hscore_sig_block"    const_sig_block :: CInt
foreign import ccall unsafe "HsBase.h __hscore_sig_setmask"  const_sig_setmask :: CInt
foreign import ccall unsafe "HsBase.h __hscore_f_getfl"      const_f_getfl :: CInt
foreign import ccall unsafe "HsBase.h __hscore_f_setfl"      const_f_setfl :: CInt
foreign import ccall unsafe "HsBase.h __hscore_f_setfd"      const_f_setfd :: CInt
foreign import ccall unsafe "HsBase.h __hscore_fd_cloexec"   const_fd_cloexec :: CLong

foreign import ccall unsafe "HsBase.h __hscore_sizeof_termios"  sizeof_termios :: Int
foreign import ccall unsafe "HsBase.h __hscore_sizeof_sigset_t" sizeof_sigset_t :: Int

foreign import ccall unsafe "HsBase.h __hscore_lflag" c_lflag :: Ptr CTermios -> IO CTcflag
foreign import ccall unsafe "HsBase.h __hscore_poke_lflag" poke_c_lflag :: Ptr CTermios -> CTcflag -> IO ()
foreign import ccall unsafe "HsBase.h __hscore_ptr_c_cc" ptr_c_cc  :: Ptr CTermios -> IO (Ptr Word8)

s_issock :: CMode -> Bool
s_issock cmode = c_s_issock cmode /= 0
foreign import capi unsafe "sys/stat.h S_ISSOCK" c_s_issock :: CMode -> CInt

foreign import ccall unsafe "__hscore_bufsiz"  dEFAULT_BUFFER_SIZE :: Int
foreign import capi  unsafe "stdio.h value SEEK_CUR" sEEK_CUR :: CInt
foreign import capi  unsafe "stdio.h value SEEK_SET" sEEK_SET :: CInt
foreign import capi  unsafe "stdio.h value SEEK_END" sEEK_END :: CInt

{-
Note: CSsize

On Win64, ssize_t is 64 bit, but functions like read return 32 bit
ints. The CAPI wrapper means the C compiler takes care of doing all
the necessary casting.

When using ccall instead, when the functions failed with -1, we thought
they were returning with 4294967295, and so didn't throw an exception.
This lead to a segfault in echo001(ghci).
-}

