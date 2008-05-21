-- -*- haskell -*-
-- This Alex file was machine-generated by the BNF converter
{
{-# OPTIONS -fno-warn-incomplete-patterns #-}
module GF.Source.LexGF where

import GF.Source.SharedString
import qualified Data.ByteString.Char8 as BS
}


$l = [a-zA-Z\192 - \255] # [\215 \247]    -- isolatin1 letter FIXME
$c = [A-Z\192-\221] # [\215]    -- capital isolatin1 letter FIXME
$s = [a-z\222-\255] # [\247]    -- small isolatin1 letter FIXME
$d = [0-9]                -- digit
$i = [$l $d _ ']          -- identifier character
$u = [\0-\255]          -- universal: any character

@rsyms =    -- symbols and non-identifier-like reserved words
   \; | \= | \{ | \} | \( | \) | \* \* | \: | \- \> | \, | \[ | \] | \- | \. | \| | \% | \? | \< | \> | \@ | \# | \! | \* | \+ | \+ \+ | \\ | \= \> | \_ | \$ | \/

:-
"--" [.]* ; -- Toss single line comments
"{-" ([$u # \-] | \- [$u # \}])* ("-")+ "}" ; 

$white+ ;
@rsyms { tok (\p s -> PT p (eitherResIdent (T_PIdent . share) s)) }
\' ($u # \')* \' { tok (\p s -> PT p (eitherResIdent (T_LString . share) s)) }
(\_ | $l)($l | $d | \_ | \')* { tok (\p s -> PT p (eitherResIdent (T_PIdent . share) s)) }

$l $i*   { tok (\p s -> PT p (eitherResIdent (TV . share) s)) }
\" ([$u # [\" \\ \n]] | (\\ (\" | \\ | \' | n | t)))* \"{ tok (\p s -> PT p (TL $ share $ unescapeInitTail s)) }

$d+      { tok (\p s -> PT p (TI $ share s))    }
$d+ \. $d+ (e (\-)? $d+)? { tok (\p s -> PT p (TD $ share s)) }

{

tok f p s = f p s

share :: BS.ByteString -> BS.ByteString
share = shareString

data Tok =
   TS !BS.ByteString !Int    -- reserved words and symbols
 | TL !BS.ByteString         -- string literals
 | TI !BS.ByteString         -- integer literals
 | TV !BS.ByteString         -- identifiers
 | TD !BS.ByteString         -- double precision float literals
 | TC !BS.ByteString         -- character literals
 | T_LString !BS.ByteString
 | T_PIdent !BS.ByteString

 deriving (Eq,Show,Ord)

data Token = 
   PT  Posn Tok
 | Err Posn
  deriving (Eq,Show,Ord)

tokenPos (PT (Pn _ l _) _ :_) = "line " ++ show l
tokenPos (Err (Pn _ l _) :_) = "line " ++ show l
tokenPos _ = "end of file"

posLineCol (Pn _ l c) = (l,c)
mkPosToken t@(PT p _) = (posLineCol p, prToken t)

prToken t = case t of
  PT _ (TS s _) -> s
  PT _ (TL s)   -> s
  PT _ (TI s)   -> s
  PT _ (TV s)   -> s
  PT _ (TD s)   -> s
  PT _ (TC s)   -> s
  PT _ (T_LString s) -> s
  PT _ (T_PIdent s) -> s


data BTree = N | B BS.ByteString Tok BTree BTree deriving (Show)

eitherResIdent :: (BS.ByteString -> Tok) -> BS.ByteString -> Tok
eitherResIdent tv s = treeFind resWords
  where
  treeFind N = tv s
  treeFind (B a t left right) | s < a  = treeFind left
                              | s > a  = treeFind right
                              | s == a = t

resWords = b "def" 39 (b "=>" 20 (b "++" 10 (b "(" 5 (b "$" 3 (b "#" 2 (b "!" 1 N N) N) (b "%" 4 N N)) (b "**" 8 (b "*" 7 (b ")" 6 N N) N) (b "+" 9 N N))) (b "/" 15 (b "->" 13 (b "-" 12 (b "," 11 N N) N) (b "." 14 N N)) (b "<" 18 (b ";" 17 (b ":" 16 N N) N) (b "=" 19 N N)))) (b "[" 30 (b "PType" 25 (b "@" 23 (b "?" 22 (b ">" 21 N N) N) (b "Lin" 24 N N)) (b "Tok" 28 (b "Strs" 27 (b "Str" 26 N N) N) (b "Type" 29 N N))) (b "case" 35 (b "_" 33 (b "]" 32 (b "\\" 31 N N) N) (b "abstract" 34 N N)) (b "concrete" 37 (b "cat" 36 N N) (b "data" 38 N N))))) (b "package" 58 (b "let" 49 (b "in" 44 (b "fun" 42 (b "fn" 41 (b "flags" 40 N N) N) (b "grammar" 43 N N)) (b "instance" 47 (b "incomplete" 46 (b "include" 45 N N) N) (b "interface" 48 N N))) (b "of" 54 (b "lindef" 52 (b "lincat" 51 (b "lin" 50 N N) N) (b "lintype" 53 N N)) (b "oper" 56 (b "open" 55 N N) (b "out" 57 N N)))) (b "transfer" 68 (b "resource" 63 (b "pre" 61 (b "pattern" 60 (b "param" 59 N N) N) (b "printname" 62 N N)) (b "table" 66 (b "strs" 65 (b "reuse" 64 N N) N) (b "tokenizer" 67 N N))) (b "with" 73 (b "variants" 71 (b "var" 70 (b "union" 69 N N) N) (b "where" 72 N N)) (b "|" 75 (b "{" 74 N N) (b "}" 76 N N)))))
   where b s n = let bs = BS.pack s
                  in B bs (TS bs n)

unescapeInitTail :: BS.ByteString -> BS.ByteString
unescapeInitTail = BS.pack . unesc . tail . BS.unpack where
  unesc s = case s of
    '\\':c:cs | elem c ['\"', '\\', '\''] -> c : unesc cs
    '\\':'n':cs  -> '\n' : unesc cs
    '\\':'t':cs  -> '\t' : unesc cs
    '"':[]    -> []
    c:cs      -> c : unesc cs
    _         -> []

-------------------------------------------------------------------
-- Alex wrapper code.
-- A modified "posn" wrapper.
-------------------------------------------------------------------

data Posn = Pn !Int !Int !Int
      deriving (Eq, Show,Ord)

alexStartPos :: Posn
alexStartPos = Pn 0 1 1

alexMove :: Posn -> Char -> Posn
alexMove (Pn a l c) '\t' = Pn (a+1)  l     (((c+7) `div` 8)*8+1)
alexMove (Pn a l c) '\n' = Pn (a+1) (l+1)   1
alexMove (Pn a l c) _    = Pn (a+1)  l     (c+1)

type AlexInput = (Posn,     -- current position,
                  Char,     -- previous char
                  BS.ByteString)   -- current input string

tokens :: BS.ByteString -> [Token]
tokens str = go (alexStartPos, '\n', str)
    where
      go :: AlexInput -> [Token]
      go inp@(pos, _, str) =
               case alexScan inp 0 of
                AlexEOF                -> []
                AlexError (pos, _, _)  -> [Err pos]
                AlexSkip  inp' len     -> go inp'
                AlexToken inp' len act -> act pos (BS.take len str) : (go inp')

alexGetChar :: AlexInput -> Maybe (Char,AlexInput)
alexGetChar (p, _, s) =
  case BS.uncons s of
    Nothing  -> Nothing
    Just (c,s) ->
             let p' = alexMove p c
              in p' `seq` Just (c, (p', c, s))

alexInputPrevChar :: AlexInput -> Char
alexInputPrevChar (p, c, s) = c
}
