{-# LANGUAGE Haskell98 #-}
{-# LINE 1 "Data/Aeson/Parser/Internal.hs" #-}







































































{-# LANGUAGE BangPatterns, CPP, OverloadedStrings #-}

-- |
-- Module:      Data.Aeson.Parser.Internal
-- Copyright:   (c) 2011, 2012 Bryan O'Sullivan
--              (c) 2011 MailRank, Inc.
-- License:     Apache
-- Maintainer:  Bryan O'Sullivan <bos@serpentine.com>
-- Stability:   experimental
-- Portability: portable
--
-- Efficiently and correctly parse a JSON string.  The string must be
-- encoded as UTF-8.

module Data.Aeson.Parser.Internal
    (
    -- * Lazy parsers
      json, jsonEOF
    , value
    , jstring
    -- * Strict parsers
    , json', jsonEOF'
    , value'
    -- * Helpers
    , decodeWith
    , decodeStrictWith
    , eitherDecodeWith
    , eitherDecodeStrictWith
    ) where

import Data.ByteString.Builder
  (Builder, byteString, toLazyByteString, charUtf8, word8)

import Control.Applicative ((*>), (<$>), (<*), liftA2, pure)
import Data.Aeson.Types (Result(..), Value(..))
import Data.Attoparsec.ByteString.Char8 (Parser, char, endOfInput, scientific,
                                         skipSpace, string)
import Data.Bits ((.|.), shiftL)
import Data.ByteString (ByteString)
import Data.Char (chr)
import Data.Monoid (mappend, mempty)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8')
import Data.Vector as Vector (Vector, fromList)
import Data.Word (Word8)
import qualified Data.Attoparsec.ByteString as A
import qualified Data.Attoparsec.Lazy as L
import qualified Data.Attoparsec.Zepto as Z
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as L
import qualified Data.ByteString.Unsafe as B
import qualified Data.HashMap.Strict as H


-- | Parse a top-level JSON value.  This must be either an object or
-- an array, per RFC 4627.
--
-- The conversion of a parsed value to a Haskell value is deferred
-- until the Haskell value is needed.  This may improve performance if
-- only a subset of the results of conversions are needed, but at a
-- cost in thunk allocation.
json :: Parser Value
json = json_ object_ array_

-- | Parse a top-level JSON value.  This must be either an object or
-- an array, per RFC 4627.
--
-- This is a strict version of 'json' which avoids building up thunks
-- during parsing; it performs all conversions immediately.  Prefer
-- this version if most of the JSON data needs to be accessed.
json' :: Parser Value
json' = json_ object_' array_'

json_ :: Parser Value -> Parser Value -> Parser Value
json_ obj ary = do
  w <- skipSpace *> A.satisfy (\w -> w == 123 || w == 91)
  if w == 123
    then obj
    else ary
{-# INLINE json_ #-}

object_ :: Parser Value
object_ = {-# SCC "object_" #-} Object <$> objectValues jstring value

object_' :: Parser Value
object_' = {-# SCC "object_'" #-} do
  !vals <- objectValues jstring' value'
  return (Object vals)
 where
  jstring' = do
    !s <- jstring
    return s

objectValues :: Parser Text -> Parser Value -> Parser (H.HashMap Text Value)
objectValues str val = do
  skipSpace
  let pair = liftA2 (,) (str <* skipSpace) (char ':' *> skipSpace *> val)
  H.fromList <$> commaSeparated pair 125
{-# INLINE objectValues #-}

array_ :: Parser Value
array_ = {-# SCC "array_" #-} Array <$> arrayValues value

array_' :: Parser Value
array_' = {-# SCC "array_'" #-} do
  !vals <- arrayValues value'
  return (Array vals)

commaSeparated :: Parser a -> Word8 -> Parser [a]
commaSeparated item endByte = do
  w <- A.peekWord8'
  if w == endByte
    then A.anyWord8 >> return []
    else loop
  where
    loop = do
      v <- item <* skipSpace
      ch <- A.satisfy $ \w -> w == 44 || w == endByte
      if ch == 44
        then skipSpace >> (v:) <$> loop
        else return [v]
{-# INLINE commaSeparated #-}

arrayValues :: Parser Value -> Parser (Vector Value)
arrayValues val = do
  skipSpace
  Vector.fromList <$> commaSeparated val 93
{-# INLINE arrayValues #-}

-- | Parse any JSON value.  You should usually 'json' in preference to
-- this function, as this function relaxes the object-or-array
-- requirement of RFC 4627.
--
-- In particular, be careful in using this function if you think your
-- code might interoperate with Javascript.  A na&#xef;ve Javascript
-- library that parses JSON data using @eval@ is vulnerable to attack
-- unless the encoded data represents an object or an array.  JSON
-- implementations in other languages conform to that same restriction
-- to preserve interoperability and security.
value :: Parser Value
value = do
  w <- A.peekWord8'
  case w of
    34  -> A.anyWord8 *> (String <$> jstring_)
    123    -> A.anyWord8 *> object_
    91   -> A.anyWord8 *> array_
    102           -> string "false" *> pure (Bool False)
    116           -> string "true" *> pure (Bool True)
    110           -> string "null" *> pure Null
    _              | w >= 48 && w <= 57 || w == 45
                  -> Number <$> scientific
      | otherwise -> fail "not a valid json value"

-- | Strict version of 'value'. See also 'json''.
value' :: Parser Value
value' = do
  w <- A.peekWord8'
  case w of
    34  -> do
                     !s <- A.anyWord8 *> jstring_
                     return (String s)
    123    -> A.anyWord8 *> object_'
    91   -> A.anyWord8 *> array_'
    102           -> string "false" *> pure (Bool False)
    116           -> string "true" *> pure (Bool True)
    110           -> string "null" *> pure Null
    _              | w >= 48 && w <= 57 || w == 45
                  -> do
                     !n <- scientific
                     return (Number n)
      | otherwise -> fail "not a valid json value"

-- | Parse a quoted JSON string.
jstring :: Parser Text
jstring = A.word8 34 *> jstring_

-- | Parse a string without a leading quote.
jstring_ :: Parser Text
jstring_ = {-# SCC "jstring_" #-} do
  s <- A.scan False $ \s c -> if s then Just False
                                   else if c == 34
                                        then Nothing
                                        else Just (c == 92)
  _ <- A.word8 34
  s1 <- if 92 `B.elem` s
        then case Z.parse unescape s of
            Right r  -> return r
            Left err -> fail err
         else return s

  case decodeUtf8' s1 of
      Right r  -> return r
      Left err -> fail $ show err

{-# INLINE jstring_ #-}

unescape :: Z.Parser ByteString
unescape = toByteString <$> go mempty where
  go acc = do
    h <- Z.takeWhile (/=92)
    let rest = do
          start <- Z.take 2
          let !slash = B.unsafeHead start
              !t = B.unsafeIndex start 1
              escape = case B.findIndex (==t) "\"\\/ntbrfu" of
                         Just i -> i
                         _      -> 255
          if slash /= 92 || escape == 255
            then fail "invalid JSON escape sequence"
            else do
            let cont m = go (acc `mappend` byteString h `mappend` m)
                {-# INLINE cont #-}
            if t /= 117 -- 'u'
              then cont (word8 (B.unsafeIndex mapping escape))
              else do
                   a <- hexQuad
                   if a < 0xd800 || a > 0xdfff
                     then cont (charUtf8 (chr a))
                     else do
                       b <- Z.string "\\u" *> hexQuad
                       if a <= 0xdbff && b >= 0xdc00 && b <= 0xdfff
                         then let !c = ((a - 0xd800) `shiftL` 10) +
                                       (b - 0xdc00) + 0x10000
                              in cont (charUtf8 (chr c))
                         else fail "invalid UTF-16 surrogates"
    done <- Z.atEnd
    if done
      then return (acc `mappend` byteString h)
      else rest
  mapping = "\"\\/\n\t\b\r\f"

hexQuad :: Z.Parser Int
hexQuad = do
  s <- Z.take 4
  let hex n | w >= 48 && w <= 57 = w - 48
            | w >= 97 && w <= 102 = w - 87
            | w >= 65 && w <= 70 = w - 55
            | otherwise          = 255
        where w = fromIntegral $ B.unsafeIndex s n
      a = hex 0; b = hex 1; c = hex 2; d = hex 3
  if (a .|. b .|. c .|. d) /= 255
    then return $! d .|. (c `shiftL` 4) .|. (b `shiftL` 8) .|. (a `shiftL` 12)
    else fail "invalid hex escape"

decodeWith :: Parser Value -> (Value -> Result a) -> L.ByteString -> Maybe a
decodeWith p to s =
    case L.parse p s of
      L.Done _ v -> case to v of
                      Success a -> Just a
                      _         -> Nothing
      _          -> Nothing
{-# INLINE decodeWith #-}

decodeStrictWith :: Parser Value -> (Value -> Result a) -> B.ByteString
                 -> Maybe a
decodeStrictWith p to s =
    case either Error to (A.parseOnly p s) of
      Success a -> Just a
      Error _ -> Nothing
{-# INLINE decodeStrictWith #-}

eitherDecodeWith :: Parser Value -> (Value -> Result a) -> L.ByteString
                 -> Either String a
eitherDecodeWith p to s =
    case L.parse p s of
      L.Done _ v -> case to v of
                      Success a -> Right a
                      Error msg -> Left msg
      L.Fail _ _ msg -> Left msg
{-# INLINE eitherDecodeWith #-}

eitherDecodeStrictWith :: Parser Value -> (Value -> Result a) -> B.ByteString
                       -> Either String a
eitherDecodeStrictWith p to s =
    case either Error to (A.parseOnly p s) of
      Success a -> Right a
      Error msg -> Left msg
{-# INLINE eitherDecodeStrictWith #-}

-- $lazy
--
-- The 'json' and 'value' parsers decouple identification from
-- conversion.  Identification occurs immediately (so that an invalid
-- JSON document can be rejected as early as possible), but conversion
-- to a Haskell value is deferred until that value is needed.
--
-- This decoupling can be time-efficient if only a smallish subset of
-- elements in a JSON value need to be inspected, since the cost of
-- conversion is zero for uninspected elements.  The trade off is an
-- increase in memory usage, due to allocation of thunks for values
-- that have not yet been converted.

-- $strict
--
-- The 'json'' and 'value'' parsers combine identification with
-- conversion.  They consume more CPU cycles up front, but have a
-- smaller memory footprint.

-- | Parse a top-level JSON value followed by optional whitespace and
-- end-of-input.  See also: 'json'.
jsonEOF :: Parser Value
jsonEOF = json <* skipSpace <* endOfInput

-- | Parse a top-level JSON value followed by optional whitespace and
-- end-of-input.  See also: 'json''.
jsonEOF' :: Parser Value
jsonEOF' = json' <* skipSpace <* endOfInput

toByteString :: Builder -> ByteString
toByteString = L.toStrict . toLazyByteString
{-# INLINE toByteString #-}
