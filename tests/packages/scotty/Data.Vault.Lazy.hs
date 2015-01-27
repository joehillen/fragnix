{-# LINE 1 "src/Data/Vault/Lazy.hs" #-}
# 1 "src/Data/Vault/Lazy.hs"
# 1 "<command-line>"
# 9 "<command-line>"
# 1 "/usr/include/stdc-predef.h" 1 3 4

# 17 "/usr/include/stdc-predef.h" 3 4














# 1 "/usr/include/x86_64-linux-gnu/bits/predefs.h" 1 3 4

# 18 "/usr/include/x86_64-linux-gnu/bits/predefs.h" 3 4












# 31 "/usr/include/stdc-predef.h" 2 3 4








# 9 "<command-line>" 2
# 1 "./dist/dist-sandbox-d76e0d17/build/autogen/cabal_macros.h" 1




































































































# 9 "<command-line>" 2
# 1 "src/Data/Vault/Lazy.hs"


-- | A persistent store for values of arbitrary types.
--
-- The 'Vault' type in this module is strict in the keys but lazy in the values.

# 1 "src/Data/Vault/IO.hs" 1
module Data.Vault.Lazy (
    -- * Vault
    Vault, Key,
    empty, newKey, lookup, insert, adjust, delete, union,

    -- * Locker
    Locker,
    lock, unlock,
    ) where

import Prelude hiding (lookup)
import Control.Monad.ST
import qualified Data.Vault.ST.Lazy as ST


{-----------------------------------------------------------------------------
    Vault
------------------------------------------------------------------------------}

-- | A persistent store for values of arbitrary types.
--
-- This variant is the simplest and creates keys in the 'IO' monad.
-- See the module "Data.Vault.ST" if you want to use it with the 'ST' monad instead.
type Vault = ST.Vault RealWorld

-- | Keys for the vault.
type Key = ST.Key RealWorld

-- | The empty vault.
empty :: Vault
empty = ST.empty

-- | Create a new key for use with a vault.
newKey :: IO (Key a)
newKey = stToIO ST.newKey

-- | Lookup the value of a key in the vault.
lookup :: Key a -> Vault -> Maybe a
lookup = ST.lookup

-- | Insert a value for a given key. Overwrites any previous value.
insert :: Key a -> a -> Vault -> Vault
insert = ST.insert

-- | Adjust the value for a given key if it's present in the vault.
adjust :: (a -> a) -> Key a -> Vault -> Vault
adjust = ST.adjust

-- | Delete a key from the vault.
delete :: Key a -> Vault -> Vault
delete = ST.delete

-- | Merge two vaults (left-biased).
union :: Vault -> Vault -> Vault
union = ST.union

{-----------------------------------------------------------------------------
    Locker
------------------------------------------------------------------------------}

-- | A persistent store for a single value.
type Locker = ST.Locker RealWorld

-- | Put a single value into a 'Locker'.
lock :: Key a -> a -> Locker
lock = ST.lock

-- | Retrieve the value from the 'Locker'.
unlock :: Key a -> Locker -> Maybe a
unlock = ST.unlock
# 7 "src/Data/Vault/Lazy.hs" 2