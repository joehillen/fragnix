{-# LINE 1 "lib/Data/Time/LocalTime/TimeZone.hs" #-}
{-# LINE 1 "dist/dist-sandbox-235ea54e/build/autogen/cabal_macros.h" #-}
                                                                

                          






                             






                     






                       






                  






                    






                        






                         






                       






                   






                      






                          







{-# LINE 2 "lib/Data/Time/LocalTime/TimeZone.hs" #-}
{-# LINE 1 "lib/Data/Time/LocalTime/TimeZone.hs" #-}
{-# OPTIONS -fno-warn-unused-imports #-}
{-# LANGUAGE ForeignFunctionInterface #-}
{-# LINE 1 "lib/include/HsConfigure.h" #-}








{-# LINE 4 "lib/Data/Time/LocalTime/TimeZone.hs" #-}

-- #hide
module Data.Time.LocalTime.TimeZone
(
	-- * Time zones
	TimeZone(..),timeZoneOffsetString,timeZoneOffsetString',minutesToTimeZone,hoursToTimeZone,utc,

	-- getting the locale time zone
	getTimeZone,getCurrentTimeZone
) where

--import System.Time.Calendar.Format
import Data.Time.Calendar.Private
import Data.Time.Clock
import Data.Time.Clock.POSIX

import Foreign.Safe
import Foreign.C
import Control.DeepSeq
import Data.Typeable




-- | A TimeZone is a whole number of minutes offset from UTC, together with a name and a \"just for summer\" flag.
data TimeZone = TimeZone {
	-- | The number of minutes offset from UTC. Positive means local time will be later in the day than UTC.
	timeZoneMinutes :: Int,
	-- | Is this time zone just persisting for the summer?
	timeZoneSummerOnly :: Bool,
	-- | The name of the zone, typically a three- or four-letter acronym.
	timeZoneName :: String
} deriving (Eq,Ord





    )

instance NFData TimeZone where
	rnf (TimeZone m so n) = m `deepseq` so `deepseq` n `deepseq` ()

-- | Create a nameless non-summer timezone for this number of minutes
minutesToTimeZone :: Int -> TimeZone
minutesToTimeZone m = TimeZone m False ""

-- | Create a nameless non-summer timezone for this number of hours
hoursToTimeZone :: Int -> TimeZone
hoursToTimeZone i = minutesToTimeZone (60 * i)

showT :: NumericPadOption -> Int -> String
showT opt t = show4 opt ((div t 60) * 100 + (mod t 60))

-- | Text representing the offset of this timezone, such as \"-0800\" or \"+0400\" (like %z in formatTime), with arbitrary padding
timeZoneOffsetString' :: NumericPadOption -> TimeZone -> String
timeZoneOffsetString' opt (TimeZone t _ _) | t < 0 = '-':(showT opt (negate t))
timeZoneOffsetString' opt (TimeZone t _ _) = '+':(showT opt t)

-- | Text representing the offset of this timezone, such as \"-0800\" or \"+0400\" (like %z in formatTime)
timeZoneOffsetString :: TimeZone -> String
timeZoneOffsetString = timeZoneOffsetString' (Just '0')

instance Show TimeZone where
	show zone@(TimeZone _ _ "") = timeZoneOffsetString zone
	show (TimeZone _ _ name) = name

-- | The UTC time zone
utc :: TimeZone
utc = TimeZone 0 False "UTC"

{-# CFILES cbits/HsTime.c #-}
foreign import ccall unsafe "HsTime.h get_current_timezone_seconds" get_current_timezone_seconds :: CTime -> Ptr CInt -> Ptr CString -> IO CLong

posixToCTime :: POSIXTime -> CTime
posixToCTime  = fromInteger . floor

-- | Get the local time-zone for a given time (varying as per summertime adjustments)
getTimeZone :: UTCTime -> IO TimeZone
getTimeZone time = with 0 (\pdst -> with nullPtr (\pcname -> do
	secs <- get_current_timezone_seconds (posixToCTime (utcTimeToPOSIXSeconds time)) pdst pcname
	case secs of
		0x80000000 -> fail "localtime_r failed"
		_ -> do
			dst <- peek pdst
			cname <- peek pcname
			name <- peekCString cname
			return (TimeZone (div (fromIntegral secs) 60) (dst == 1) name)
	))

-- | Get the current time-zone
getCurrentTimeZone :: IO TimeZone
getCurrentTimeZone = getCurrentTime >>= getTimeZone
