{-# LANGUAGE Haskell98 #-}
{-# LINE 1 "Blaze/ByteString/Builder/Internal/UncheckedShifts.hs" #-}













































{-# LANGUAGE CPP, MagicHash #-}


-- |
-- Module      : Blaze.ByteString.Builder.Internal.UncheckedShifts
-- Copyright   : (c) 2010 Simon Meier
--
--               Original serialization code from 'Data.Binary.Builder':
--               (c) Lennart Kolmodin, Ross Patterson
--
-- License     : BSD3-style (see LICENSE)
--
-- Maintainer  : Simon Meier <iridcode@gmail.com>
-- Stability   : experimental
-- Portability : tested on GHC only
--
-- Utilty module defining unchecked shifts.
--













































































































































































































































































































































module Blaze.ByteString.Builder.Internal.UncheckedShifts (
    shiftr_w16
  , shiftr_w32
  , shiftr_w64
  ) where

-- TODO: Check validity of this implementation

import GHC.Base
import GHC.Word (Word32(..),Word16(..),Word64(..))



------------------------------------------------------------------------
-- Unchecked shifts

{-# INLINE shiftr_w16 #-}
shiftr_w16 :: Word16 -> Int -> Word16
{-# INLINE shiftr_w32 #-}
shiftr_w32 :: Word32 -> Int -> Word32
{-# INLINE shiftr_w64 #-}
shiftr_w64 :: Word64 -> Int -> Word64

shiftr_w16 (W16# w) (I# i) = W16# (w `uncheckedShiftRL#`   i)
shiftr_w32 (W32# w) (I# i) = W32# (w `uncheckedShiftRL#`   i)

shiftr_w64 (W64# w) (I# i) = W64# (w `uncheckedShiftRL#` i)


