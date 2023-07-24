module Data
  ( Data,
    arbitrary,
    raw,
    fromHex,
    fromHex',
    fromBase64,
    toHex,
    toBase64,
    toBytes,
    toString,
    len,
    lrotate,
    showBin,
  )
where

import Data.Bifunctor
import Data.Bits (Bits (complement), bit, popCount, rotateL, rotateR, shiftL, shiftR, testBit, xor, (.&.), (.|.))
import Data.Bits qualified
import Data.ByteString qualified as B
import Data.ByteString.Base64 qualified as B64
import Data.ByteString.UTF8 qualified as BU
import GHC.Word (Word8)
import Numeric qualified as N
import Test.QuickCheck (Arbitrary, arbitrary)

-- Generic functions to manipulate bytes and bits

newtype Data = Data B.ByteString deriving (Eq)

instance Show Data where
  show d =
    "Data <" <> toHex d <> ">"

pad :: String -> String
pad l =
  if even (length l)
    then l
    else '0' : l

raw :: String -> Data
raw =
  Data . BU.fromString

fromHex :: String -> Data
fromHex h =
  Data $ B.pack $ map (toInt . N.readHex) $ pairUp $ pad h
  where
    toInt ((v, _) : _) = v
    toInt [] = 0
    pairUp (x : x' : t) = [x, x'] : pairUp t
    pairUp [_] = [] -- This only happens if your string is unpadded
    pairUp [] = []

fromHex' :: String -> B.ByteString
fromHex' h =
  B.pack $ map (toInt . N.readHex) $ pairUp $ pad h
  where
    toInt ((v, _) : _) = v
    toInt [] = 0
    pairUp (x : x' : t) = [x, x'] : pairUp t
    pairUp [_] = [] -- This only happens if your string is unpadded
    pairUp [] = []

toHex :: Data -> String
toHex (Data s) =
  B.foldl (\acc c -> acc ++ pad (N.showHex c "")) [] s

fromBase64 :: String -> Either String Data
fromBase64 h =
  second Data $ B64.decode $ BU.fromString h

toBase64 :: Data -> String
toBase64 (Data s) =
  BU.toString $ B64.encode s

toBytes :: Data -> [Int]
toBytes (Data d) = map fromIntegral $ B.unpack d

toString :: Data -> String
toString (Data d) = BU.toString d

len :: Data -> Int
len (Data d) = B.length d

-- Helpers

applyBitwiseOperation :: (Word8 -> Word8) -> Data -> Data
applyBitwiseOperation operation (Data d) =
  Data $ B.map operation d

applyBitwiseOperation2 :: (Word8 -> Word8 -> Word8) -> Data -> Data -> Data
applyBitwiseOperation2 operation (Data d1) (Data d2) =
  Data $ B.packZipWith operation d1 d2

lrotate :: [a] -> Int -> [a]
lrotate xs n
  | l == 0 = []
  | n < 0 = lrotate xs (l + (n `mod` l))
  | n == 0 = xs
  | otherwise = drop (n `mod` l) xs <> take (n `mod` l) xs
  where
    l = length xs

showBin :: Data -> String
showBin (Data d) =
  mconcat $ map (padTo8 . (`N.showBin` "")) $ reverse $ B.unpack d
  where
    padTo8 s
      | length s < 8 = replicate (8 - length s) '0' <> s
      | otherwise = s

-- Make it a Data.Bits instance, so that we get bit manipulation functions

instance Data.Bits.Bits Data where
  (.&.) = applyBitwiseOperation2 (.&.)
  (.|.) = applyBitwiseOperation2 (.|.)
  xor = applyBitwiseOperation2 xor
  complement = applyBitwiseOperation complement
  shiftR (Data d) i
    -- Shift bits to the right, removing words
    | B.length d == 0 = Data d
    | 0 < i && i < 8 = Data $ B.pack $ zipWith shiftWithBitsOfNextWord data_words data_words_shifted
    | i >= 8 = shiftR (Data $ B.pack $ take (B.length d - i `div` 8) unpacked) rest
    | otherwise = Data d
    where
      unpacked = B.unpack d
      data_words = take (B.length d - 1) unpacked -- Cut the last word
      data_words_shifted = drop 1 unpacked <> [0]
      rest = i `mod` 8 -- Remaining shift after having shifted entire words
      shiftWithBitsOfNextWord w next_w =
        -- Shift w by i bits to the right, and fill the
        -- right-most bits with the right-most withs of next_w.
        shiftR w i + shiftL next_w (8 - i)
  shiftL (Data d) i
    -- Shift bits to the left, filling with 0's and extending the data string
    | 0 < i && i < 8 = Data $ B.pack $ zipWith shiftWithBitsOfPrevWord data_words data_words_shifted
    | i >= 8 = shiftL (Data $ B.pack (B.unpack d <> zero_words)) rest
    | otherwise = Data d
    where
      data_words = B.unpack d <> [0] -- Expand the bytestring with one new word to account for the new bits
      data_words_shifted = 0 : data_words
      zero_words = replicate (i `div` 8) 0
      rest = i `mod` 8
      shiftWithBitsOfPrevWord w prev_w =
        -- Shift w by i bits to the left, and fill the
        -- right-most bits with the left-most withs of prev_w.
        shiftL w i + shiftR prev_w (8 - i)
  bitSizeMaybe _ = Nothing -- Our container doesn't have a fixed bitsize
  bitSize (Data d) = 8 * B.length d -- This isn't 100% coherent with the spec, but its useful
  isSigned _ = False
  testBit (Data d) i
    | 0 <= i && i < B.length d * 8 = testBit (B.unpack d !! (i `div` 8)) (i `mod` 8)
    | otherwise = False
  popCount (Data d) =
    sum $ map popCount $ B.unpack d
  bit i =
    Data $ B.pack $ replicate (i `div` 8) 0 <> [bit (i `mod` 8)]
  rotateL (Data d) i
    | i == 0 = Data d
    | i < 8 = Data $ B.pack $ zipWith rotateWordsL data_words data_words_shifted
    | otherwise = rotateL (Data $ B.pack $ lrotate (B.unpack d) (i `div` 8)) (i `mod` 8)
    where
      data_words = B.unpack d
      data_words_shifted = lrotate data_words 1
      rotateWordsL w prev_w =
        -- Rotate a word by shifting to the next or previous words,
        -- depending on direction of rotation
        shiftL w i + shiftR prev_w (8 - i)
  rotateR (Data d) i
    | i == 0 = Data d
    | i < 8 = Data $ B.pack $ zipWith rotateWordsR data_words data_words_shifted
    | otherwise = rotateR (Data $ B.pack $ lrotate (B.unpack d) (negate (i `div` 8))) (i `mod` 8)
    where
      data_words = B.unpack d
      data_words_shifted = lrotate data_words (-1)
      rotateWordsR w next_w =
        -- Rotate a word by shifting to the next or previous words,
        -- depending on direction of rotation
        shiftR w i + shiftL next_w (8 - i)

-- Allow QuickCheck testing of Data

instance Arbitrary Data where
  arbitrary = do
    Data.raw <$> arbitrary
