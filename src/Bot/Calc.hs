{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE QuasiQuotes #-}

module Bot.Calc
  ( calcCommand
  ) where

import Bot.Replies
import Data.Char (isDigit)
import Data.Either.Extra
import Data.Foldable
import qualified Data.Text as T
import Reaction
import Safe
import Text.InterpolatedString.QM
import Transport

data Op
  = Plus
  | Minus
  | Multiply
  | Division
  | Mod
  deriving (Eq, Show)

data Token
  = NumberToken Int
  | OpToken Op
  deriving (Eq, Show)

tokenize :: T.Text -> Either String [Token]
tokenize (T.uncons -> Just (' ', xs)) = tokenize xs
tokenize (T.uncons -> Just ('+', xs)) = (OpToken Plus :) <$> tokenize xs
tokenize (T.uncons -> Just ('-', xs)) = (OpToken Minus :) <$> tokenize xs
tokenize (T.uncons -> Just ('*', xs)) = (OpToken Multiply :) <$> tokenize xs
tokenize (T.uncons -> Just ('/', xs)) = (OpToken Division :) <$> tokenize xs
tokenize (T.uncons -> Just ('%', xs)) = (OpToken Mod :) <$> tokenize xs
-- TODO(#574): !calc does not support fractional numbers
tokenize (T.uncons -> Just ('.', _)) =
  Left "https://github.com/tsoding/HyperNerd/issues/574"
-- TODO(#571): Parenthesis are not supported by !calc
-- TODO(#573): !calc does not support negative numbers
-- TODO(#567): !calc Int overflow is not reported as an error
tokenize xs@(T.uncons -> Just (x, _))
  | x `elem` ['(', ')'] = Left "https://github.com/tsoding/HyperNerd/issues/571"
  | isDigit x = do
    token <-
      NumberToken <$>
      maybeToEither
        [qms|{digits} does not look like a number|]
        (readMay $ T.unpack digits)
    (token :) <$> tokenize rest
  | otherwise = Left [qms|I don't know what's this `{x}`|]
  where
    (digits, rest) = T.span isDigit xs
tokenize (T.uncons -> Nothing) = return []
tokenize _ = Left "Error 😡"

precedence :: Op -> Int
precedence Plus = 0
precedence Minus = 0
precedence Multiply = 1
precedence Division = 1
precedence Mod = 1

infixToRpn :: [Op] -> [Token] -> Either String [Token]
infixToRpn opStack (NumberToken x:restTokens) =
  (NumberToken x :) <$> infixToRpn opStack restTokens
infixToRpn [] (OpToken op:rest) = infixToRpn [op] rest
infixToRpn opStack@(op0:_) (OpToken op1:rest)
  | precedence op0 < precedence op1 = infixToRpn (op1 : opStack) rest
  | otherwise =
    (map OpToken outputOps ++) <$> infixToRpn (op1 : restOpStack) rest
  where
    (outputOps, restOpStack) =
      span (\opx -> precedence opx >= precedence op1) opStack
infixToRpn opStack [] = return $ map OpToken opStack

type RpnState = [Int]

divEither :: Integral a => a -> a -> Either String a
divEither _ 0 = Left "Division by zero"
divEither a b = return $ div a b

modEither :: Integral a => a -> a -> Either String a
modEither _ 0 = Left "Division by zero"
modEither a b = return $ mod a b

interpretOp :: Op -> Int -> Int -> Either String Int
interpretOp Plus a b = return (a + b)
interpretOp Minus a b = return (a - b)
interpretOp Multiply a b = return (a * b)
interpretOp Division a b = divEither a b
interpretOp Mod a b = modEither a b

interpretToken :: RpnState -> Token -> Either String RpnState
interpretToken s (NumberToken x) = return (x : s)
interpretToken (x1:x2:xs) (OpToken op) = (: xs) <$> interpretOp op x2 x1
interpretToken _ _ = Left "Error 😡"

interpretRpn :: [Token] -> Either String Int
interpretRpn tokens = do
  result <- foldlM interpretToken [] tokens
  case result of
    [x] -> return x
    _ -> Left "Error 😡"

calc :: T.Text -> Either String Int
calc text = do
  tokens <- tokenize text
  rpn <- infixToRpn [] tokens
  interpretRpn rpn

calcCommand :: Reaction Message T.Text
calcCommand =
  cmapR calc $ replyLeft $ cmapR (T.pack . show) $ Reaction replyMessage