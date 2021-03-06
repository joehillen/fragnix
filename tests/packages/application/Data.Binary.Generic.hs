{-# LANGUAGE Haskell98 #-}
{-# LINE 1 "src/Data/Binary/Generic.hs" #-}















































{-# LANGUAGE BangPatterns, CPP, FlexibleInstances, KindSignatures,
    ScopedTypeVariables, Trustworthy, TypeOperators, TypeSynonymInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

-----------------------------------------------------------------------------
-- |
-- Module      : Data.Binary.Generic
-- Copyright   : Bryan O'Sullivan
-- License     : BSD3-style (see LICENSE)
--
-- Maintainer  : Bryan O'Sullivan <bos@serpentine.com>
-- Stability   : unstable
-- Portability : Only works with GHC 7.2 and newer
--
-- Instances for supporting GHC generics.
--
-----------------------------------------------------------------------------
module Data.Binary.Generic
    (
    ) where

import Control.Applicative
import Data.Binary.Class
import Data.Binary.Get
import Data.Binary.Put
import Data.Bits
import Data.Word
import GHC.Generics

-- Type without constructors
instance GBinary V1 where
    gput _ = return ()
    gget   = return undefined

-- Constructor without arguments
instance GBinary U1 where
    gput U1 = return ()
    gget    = return U1

-- Product: constructor with parameters
instance (GBinary a, GBinary b) => GBinary (a :*: b) where
    gput (x :*: y) = gput x >> gput y
    gget = (:*:) <$> gget <*> gget

-- Metadata (constructor name, etc)
instance GBinary a => GBinary (M1 i c a) where
    gput = gput . unM1
    gget = M1 <$> gget

-- Constants, additional parameters, and rank-1 recursion
instance Binary a => GBinary (K1 i a) where
    gput = put . unK1
    gget = K1 <$> get

-- Borrowed from the cereal package.

-- The following GBinary instance for sums has support for serializing
-- types with up to 2^64-1 constructors. It will use the minimal
-- number of bytes needed to encode the constructor. For example when
-- a type has 2^8 constructors or less it will use a single byte to
-- encode the constructor. If it has 2^16 constructors or less it will
-- use two bytes, and so on till 2^64-1.


instance ( GSum     a, GSum     b
         , GBinary a, GBinary b
         , SumSize    a, SumSize    b) => GBinary (a :+: b) where
    gput | (size - 1) <= fromIntegral (maxBound :: Word8) = putSum (0 :: Word8) (fromIntegral size) | (size - 1) <= fromIntegral (maxBound :: Word16) = putSum (0 :: Word16) (fromIntegral size) | (size - 1) <= fromIntegral (maxBound :: Word32) = putSum (0 :: Word32) (fromIntegral size) | (size - 1) <= fromIntegral (maxBound :: Word64) = putSum (0 :: Word64) (fromIntegral size)
         | otherwise = sizeError "encode" size
      where
        size = unTagged (sumSize :: Tagged (a :+: b) Word64)

    gget | (size - 1) <= fromIntegral (maxBound :: Word8) = (get :: Get Word8) >>= checkGetSum (fromIntegral size) | (size - 1) <= fromIntegral (maxBound :: Word16) = (get :: Get Word16) >>= checkGetSum (fromIntegral size) | (size - 1) <= fromIntegral (maxBound :: Word32) = (get :: Get Word32) >>= checkGetSum (fromIntegral size) | (size - 1) <= fromIntegral (maxBound :: Word64) = (get :: Get Word64) >>= checkGetSum (fromIntegral size)
         | otherwise = sizeError "decode" size
      where
        size = unTagged (sumSize :: Tagged (a :+: b) Word64)

sizeError :: Show size => String -> size -> error
sizeError s size =
    error $ "Can't " ++ s ++ " a type with " ++ show size ++ " constructors"

------------------------------------------------------------------------

checkGetSum :: (Ord word, Num word, Bits word, GSum f)
            => word -> word -> Get (f a)
checkGetSum size code | code < size = getSum code size
                      | otherwise   = fail "Unknown encoding for constructor"
{-# INLINE checkGetSum #-}

class GSum f where
    getSum :: (Ord word, Num word, Bits word) => word -> word -> Get (f a)
    putSum :: (Num w, Bits w, Binary w) => w -> w -> f a -> Put

instance (GSum a, GSum b, GBinary a, GBinary b) => GSum (a :+: b) where
    getSum !code !size | code < sizeL = L1 <$> getSum code           sizeL
                       | otherwise    = R1 <$> getSum (code - sizeL) sizeR
        where
          sizeL = size `shiftR` 1
          sizeR = size - sizeL

    putSum !code !size s = case s of
                             L1 x -> putSum code           sizeL x
                             R1 x -> putSum (code + sizeL) sizeR x
        where
          sizeL = size `shiftR` 1
          sizeR = size - sizeL

instance GBinary a => GSum (C1 c a) where
    getSum _ _ = gget

    putSum !code _ x = put code *> gput x

------------------------------------------------------------------------

class SumSize f where
    sumSize :: Tagged f Word64

newtype Tagged (s :: * -> *) b = Tagged {unTagged :: b}

instance (SumSize a, SumSize b) => SumSize (a :+: b) where
    sumSize = Tagged $ unTagged (sumSize :: Tagged a Word64) +
                       unTagged (sumSize :: Tagged b Word64)

instance SumSize (C1 c a) where
    sumSize = Tagged 1
