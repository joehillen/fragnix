{-# LANGUAGE Haskell2010 #-}
{-# LINE 1 "System/Info.hs" #-}













































{-# LANGUAGE Safe #-}
{-# LANGUAGE CPP #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  System.Info
-- Copyright   :  (c) The University of Glasgow 2001
-- License     :  BSD-style (see the file libraries/base/LICENSE)
-- 
-- Maintainer  :  libraries@haskell.org
-- Stability   :  experimental
-- Portability :  portable
--
-- Information about the characteristics of the host 
-- system lucky enough to run your program.
--
-----------------------------------------------------------------------------

module System.Info
   (
       os,
       arch,
       compilerName,
       compilerVersion
   ) where

import Prelude
import Data.Version

-- | The version of 'compilerName' with which the program was compiled
-- or is being interpreted.
compilerVersion :: Version
compilerVersion = Version {versionBranch=[major, minor], versionTags=[]}
  where (major, minor) = compilerVersionRaw `divMod` 100










-- | The operating system on which the program is running.
os :: String
os = "linux"

-- | The machine architecture on which the program is running.
arch :: String
arch = "x86_64"

-- | The Haskell implementation with which the program was compiled
-- or is being interpreted.
compilerName :: String
compilerName = "ghc"

compilerVersionRaw :: Int
compilerVersionRaw = 708
