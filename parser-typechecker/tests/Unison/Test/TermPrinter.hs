{-# Language OverloadedStrings #-}

module Unison.Test.TermPrinter (test) where

import EasyTest
import qualified Data.Text as Text
import Unison.ABT (annotation)
import qualified Unison.HashQualified as HQ
import Unison.Term
import Unison.TermPrinter
import qualified Unison.Type as Type
import Unison.Symbol (Symbol, symbol)
import qualified Unison.Builtin
import Unison.Parser (Ann(..))
import qualified Unison.Util.Pretty as PP
import qualified Unison.PrettyPrintEnv as PPE
import qualified Unison.Util.ColorText as CT
import Unison.Test.Common (t, tm)
import qualified Unison.Test.Common as Common

getNames :: PPE.PrettyPrintEnv
getNames = PPE.fromNames Common.hqLength Unison.Builtin.names

-- Test the result of the pretty-printer.  Expect the pretty-printer to
-- produce output that differs cosmetically from the original code we parsed.
-- Check also that re-parsing the pretty-printed code gives us the same ABT.
-- (Skip that latter check if rtt is false.)
-- Note that this does not verify the position of the PrettyPrint Break elements.
tcDiffRtt :: Bool -> String -> String -> Int -> Test ()
tcDiffRtt rtt s expected width
  = let
      inputTerm = tm s :: Unison.Term.AnnotatedTerm Symbol Ann
      prettied  = CT.toPlain <$> pretty getNames inputTerm
      actual    = if width == 0
        then PP.renderUnbroken prettied
        else PP.render width prettied
      actualReparsed = tm actual
    in
      scope s $ tests
        [ if actual == expected
          then ok
          else do
            note $ "expected:\n" ++ expected
            note $ "actual:\n" ++ actual
            note $ "show(input)  : " ++ show inputTerm
            note $ "prettyprint  : " ++ show prettied
            crash "actual != expected"
        , if not rtt || (inputTerm == actualReparsed)
          then ok
          else do
            note "round trip test..."
            note $ "single parse: " ++ show inputTerm
            note $ "double parse: " ++ show actualReparsed
            note $ "prettyprint  : " ++ show prettied
            crash "single parse != double parse"
        ]

-- As above, but do the round-trip test unconditionally.
tcDiff :: String -> String -> Test ()
tcDiff s expected = tcDiffRtt True s expected 0

-- As above, but expect not even cosmetic differences between the input string
-- and the pretty-printed version.
tc :: String -> Test ()
tc s = tcDiff s s

-- Use renderBroken to render the output to some maximum width.
tcBreaksDiff :: Int -> String -> String -> Test ()
tcBreaksDiff width s expected = tcDiffRtt True s expected width

tcBreaks :: Int -> String -> Test ()
tcBreaks width s = tcDiffRtt True s s width

tcBinding :: Int -> String -> Maybe String -> String -> String -> Test ()
tcBinding width v mtp tm expected
  = let
      baseTerm =
        Unison.Test.Common.tm tm :: Unison.Term.AnnotatedTerm Symbol Ann
      inputType = fmap Unison.Test.Common.t mtp :: Maybe (Type.Type Symbol Ann)
      inputTerm (Just tp) = ann (annotation tp) baseTerm tp
      inputTerm Nothing   = baseTerm
      varV     = symbol $ Text.pack v
      prettied = fmap CT.toPlain $ PP.syntaxToColor $ prettyBinding
        getNames
        (HQ.unsafeFromVar varV)
        (inputTerm inputType)
      actual = if width == 0
        then PP.renderUnbroken prettied
        else PP.render width prettied
    in
      scope expected $ tests
        [ if actual == expected
            then ok
            else do
              note $ "expected: " ++ show expected
              note $ "actual  : " ++ show actual
              note $ "show(input)  : " ++ show (inputTerm inputType)
              note $ "prettyprint  : " ++ show prettied
              crash "actual != expected"
        ]

test :: Test ()
test = scope "termprinter" . tests $
  [ tc "if true then +2 else -2"
  , tc "[2, 3, 4]"
  , tc "[2]"
  , tc "[]"
  , tc "and true false"
  , tc "or false false"
  , tc "g (and (or true false) (f x y))"
  , tc "if _something then _foo else _blah"
  , tc "3.14159"
  , tc "+0"
  , tc "\"some text\""
  , pending $ tc "\"they said \\\"hi\\\"\""  -- TODO lexer doesn't support strings with quotes in
  , tc "2 : Nat"
  , tc "x -> and x false"
  , tc "x y -> and x y"
  , tc "x y z -> and x y"
  , tc "x y y -> and x y"
  , tc "()"
  , tc "Cons"
  , tc "foo"
  , tc "List.empty"
  , tc "None"
  , tc "Optional.None"
  , tc "handle foo in bar"
  , tc "Cons 1 1"
  , tc "let\n\
       \  x = 1\n\
       \  x"
  , tcBreaks 50 "let\n\
                 \  x = 1\n\
                 \  x"
  , tcBreaks 50 "let\n\
                 \  x = 1\n\
                 \  y = 2\n\
                 \  f x y"
  , tcBreaks 50 "let\n\
                 \  x = 1\n\
                 \  x = 2\n\
                 \  f x x"
  , pending $ tc "case x of Pair t 0 -> foo t" -- TODO hitting UnknownDataConstructor when parsing pattern
  , pending $ tc "case x of Pair t 0 | pred t -> foo t" -- ditto
  , pending $ tc "case x of Pair t 0 | pred t -> foo t; Pair t 0 -> foo' t; Pair t u -> bar;" -- ditto
  , tc "case x of () -> foo"
  , tc "case x of _ -> foo"
  , tc "case x of y -> y"
  , tc "case x of 1 -> foo"
  , tc "case x of +1 -> foo"
  , tc "case x of -1 -> foo"
  , tc "case x of 3.14159 -> foo"
  , tcDiffRtt False "case x of\n\
                      \  true -> foo\n\
                      \  false -> bar"
                      "case x of\n  true -> foo\n  false -> bar" 0
  , tcBreaks 50 "case x of\n\
                 \  true -> foo\n\
                 \  false -> bar"
  , tc "case x of false -> foo"
  , tc "case x of y@() -> y"
  , tc "case x of a@(b@(c@())) -> c"
  , tc "case e of { a } -> z"
  , pending $ tc "case e of { () -> k } -> z" -- TODO doesn't parse since 'many leaf' expected before the "-> k"
                                              -- need an actual effect constructor to test this with
  , tc "if a then if b then c else d else e"
  , tc "handle foo in (handle bar in baz)"
  , tcBreaks 16 "case (if a then\n\
                 \  b\n\
                 \else c) of\n\
                 \  112 -> x"        -- dodgy layout.  note #517 and #518
  , tc "handle Pair 1 1 in bar"
  , tc "handle x -> foo in bar"
  , tcDiffRtt True "let\n\
                     \  x = (1 : Int)\n\
                     \  (x : Int)"
                     "let\n\
                     \  x : Int\n\
                     \  x = 1\n\
                     \  (x : Int)" 50
  , tc "case x of 12 -> (y : Int)"
  , tc "if a then (b : Int) else (c : Int)"
  , tc "case x of 12 -> if a then b else c"
  , tc "case x of 12 -> x -> f x"
  , tcDiff "case x of (12) -> x" "case x of 12 -> x"
  , tcDiff "case (x) of 12 -> x" "case x of 12 -> x"
  , tc "case x of 12 -> x"
  , tcDiffRtt True "case x of\n\
                     \  12 -> x"
                     "case x of 12 -> x" 50
  , tcBreaks 15 "case x of\n\
                 \  12 -> x\n\
                 \  13 -> y\n\
                 \  14 -> z"
  , tcBreaks 21 "case x of\n\
                 \  12 | p x -> x\n\
                 \  13 | q x -> y\n\
                 \  14 | r x y -> z"
  , tcBreaks 9 "case x of\n\
                \  112 ->\n\
                \    x\n\
                \  113 ->\n\
                \    y\n\
                \  114 ->\n\
                \    z"
  , pending $ tcBreaks 19 "case\n\
                           \  myFunction\n\
                           \    argument1\n\
                           \    argument2\n\
                           \of\n\
                           \  112 -> x"          -- TODO, 'unexpected semi' before 'of' - should the parser accept this?
  , tc "if c then x -> f x else x -> g x"
  , tc "(f x) : Int"
  , tc "(f x) : Pair Int Int"
  , tcBreaks 50 "let\n\
                 \  x = if a then b else c\n\
                 \  if x then y else z"
  , tc "f x y"
  , tc "f x y z"
  , tc "f (g x) y"
  , tcDiff "(f x) y" "f x y"
  , pending $ tc "1.0e-19"         -- TODO parser throws UnknownLexeme
  , pending $ tc "-1.0e19"         -- ditto
  , tc "0.0"
  , tc "-0.0"
  , pending $ tcDiff "+0.0" "0.0"  -- TODO parser throws "Prelude.read: no parse" - should it?  Note +0 works for UInt.
  , tcBreaksDiff 21 "case x of 12 -> if a then b else c"
              "case x of\n\
              \  12 ->\n\
              \    if a then b\n\
              \    else c"
  , tcDiffRtt True "if foo\n\
            \then\n\
            \  and true true\n\
            \  12\n\
            \else\n\
            \  namespace baz where\n\
            \    f : Int -> Int\n\
            \    f x = x\n\
            \  13"
            "if foo then\n\
            \  and true true\n\
            \  12\n\
            \else\n\
            \  baz.f : Int -> Int\n\
            \  baz.f x = x\n\
            \  13" 50
  , tcBreaks 50 "if foo then\n\
                 \  and true true\n\
                 \  12\n\
                 \else\n\
                 \  baz.f : Int -> Int\n\
                 \  baz.f x = x\n\
                 \  13"
  , pending $ tcBreaks 90 "handle foo in\n\
                 \  a = 5\n\
                 \  b =\n\
                 \    c = 3\n\
                 \    true\n\
                 \  false"  -- TODO comes back out with line breaks around foo
  , tcBreaks 50 "case x of\n\
                 \  true ->\n\
                 \    d = 1\n\
                 \    false\n\
                 \  false ->\n\
                 \    f x = x + 1\n\
                 \    true"
  , pending $ tcBreaks 50 "x -> e = 12\n\
                 \     x + 1"  -- TODO parser looks like lambda body should be a block, but we hit 'unexpected ='
  , tc "x + y"
  , tc "x ~ y"
  , tcDiff "x `foo` y" "foo x y"
  , tc "x + (y + z)"
  , tc "x + y + z"
  , tc "x + y * z" -- i.e. (x + y) * z !
  , tc "x \\ y == z ~ a"
  , tc "foo x (y + z)"
  , tc "foo (x + y) z"
  , tc "foo x y + z"
  , tc "foo p q + r + s"
  , tc "foo (p + q) r + s"
  , tc "foo (p + q + r) s"
  , tc "p + q + r + s"
  , tcDiffRtt False "(foo.+) x y" "x foo.+ y" 0
  , tc "x + y + f a b c"
  , tc "x + y + foo a b"
  , tc "foo x y p + z"
  , tc "foo p q a + r + s"
  , tc "foo (p + q) r a + s"
  , tc "foo (x + y) (p - q)"
  , tc "x -> x + y"
  , tc "if p then x + y else a - b"
  , tc "(x + y) : Int"
  , tc "!foo"
  , tc "!(foo a b)"
  , tc "!f a"
  , tcDiff "f () a ()" "!(!f a)"
  , tcDiff "f a b ()" "!(f a b)"
  , tcDiff "!f ()" "!(!f)"
  , tc "!(!foo)"
  , tc "'bar"
  , tc "'(bar a b)"
  , tc "'('bar)"
  , tc "!('bar)"
  , tc "'(!foo)"
  , tc "x -> '(y -> 'z)"
  , tc "'(x -> '(y -> z))"
  , tc "(\"a\", 2)"
  , tc "(\"a\", 2, 2.0)"
  , tcDiff "(2)" "2"
  , pending $ tcDiff "Pair \"2\" (Pair 2 ())" "(\"2\", 2)"  -- TODO parser produced
                                                     --  Pair "2" (Pair 2 ()#0)
                                                     -- instead of
                                                     --  Pair#0 "2" (Pair#0 2 ()#0)
                                                     -- Maybe because in this context the
                                                     -- parser can't distinguish between a constructor
                                                     -- called 'Pair' and a function called 'Pair'.
  , pending $ tc "Pair 2 ()"  -- unary tuple; fails for same reason as above
  , tc "case x of (a, b) -> a"
  , tc "case x of () -> foo"
  , pending $ tc "case x of [a, b] -> a"  -- issue #266
  , pending $ tc "case x of [a] -> a"     -- ditto
  , pending $ tc "case x of [] -> a"      -- ditto
  , tc "case x of Optional.Some (Optional.Some _) -> ()" -- Issue #695
  -- need an actual effect constructor to test the following
  , pending $ tc "case x of { SomeRequest (Optional.Some _) -> k } -> ()" 
  , tcBinding 50 "foo" (Just "Int") "3" "foo : Int\n\
                                         \foo = 3"
  , tcBinding 50 "foo" Nothing "3" "foo = 3"
  , tcBinding 50 "foo" (Just "Int -> Int") "n -> 3" "foo : Int -> Int\n\
                                                     \foo n = 3"
  , tcBinding 50 "foo" Nothing "n -> 3" "foo n = 3"
  , tcBinding 50 "foo" Nothing "n m -> 3" "foo n m = 3"
  , tcBinding 9 "foo" Nothing "n m -> 3" "foo n m =\n\
                                          \  3"
  , tcBinding 50 "+" (Just "Int -> Int -> Int") "a b -> foo a b" "(+) : Int -> Int -> Int\n\
                                                                  \a + b = foo a b"
  , tcBinding 50 "+" (Just "Int -> Int -> Int -> Int") "a b c -> foo a b c" "(+) : Int -> Int -> Int -> Int\n\
                                                                             \(+) a b c = foo a b c"
  , tcBinding 50 "+" Nothing "a b -> foo a b" "a + b = foo a b"
  , tcBinding 50 "+" Nothing "a b c -> foo a b c" "(+) a b c = foo a b c"
  , tcBreaks 32 "let\n\
                 \  go acc a b =\n\
                 \    case List.at 0 a of\n\
                 \      Optional.None -> 0\n\
                 \      Optional.Some hd1 -> 0\n\
                 \  go [] a b"
  , tcBreaks 30 "case x of\n\
                 \  (Optional.None, _) -> foo"
  , tcBreaks 50 "if true then case x of 12 -> x else x"
  , tcBreaks 50 "if true then x else case x of 12 -> x"
  , pending $ tcBreaks 80 "x -> (if c then t else f)"  -- TODO 'unexpected )', surplus parens
  , tcBreaks 80 "'let\n\
                 \  foo = bar\n\
                 \  baz foo"
  , tcBreaks 80 "!let\n\
                 \  foo = bar\n\
                 \  baz foo"
  , tcDiffRtt True "foo let\n\
                     \      a = 1\n\
                     \      b"
                     "foo\n\
                     \  let\n\
                     \    a = 1\n\
                     \    b" 80
  , tcBreaks 80 "if\n\
                 \  a = b\n\
                 \  a then foo else bar"   -- missing break before 'then', issue #518
  , tcBreaks 80 "Stream.foldLeft 0 (+) t"
  , tcBreaks 80 "foo?"
  , tcBreaks 80 "(foo a b)?"
  , tcDiffRtt False "let\n\
                      \  delay = 'isEven"
                      "let\n\
                      \  delay () = isEven\n\
                      \  _" 80 -- TODO the latter doesn't parse - can't handle the () on the LHS
  , tcBreaks 80 "let\n\
                 \  a = ()\n\
                 \  b = ()\n\
                 \  c = (1, 2)\n\
                 \  ()"

-- FQN elision tests
  , tcBreaks 12 "if foo then\n\
                 \  use A x\n\
                 \  f x x\n\
                 \else\n\
                 \  use B y\n\
                 \  f y y"
  , tcBreaks 12 "if foo then\n\
                 \  use A x\n\
                 \  f x x\n\
                 \else\n\
                 \  use B x\n\
                 \  f x x"
  , tcBreaks 80 "let\n\
                 \  a =\n\
                 \    use A x\n\
                 \    if foo then f x x else g x x\n\
                 \  bar"
  , tcBreaks 80 "if foo then f A.x B.x else f A.x B.x"
  , tcBreaks 80 "if foo then f A.x A.x B.x else y"
  , tcBreaks 80 "if foo then A.f x else y"
  , tcBreaks 13 "if foo then\n\
                 \  use A +\n\
                 \  x + y\n\
                 \else y"
  , tcBreaks 20 "if p then\n\
                 \  use A x\n\
                 \  use B y z\n\
                 \  f z z y y x x\n\
                 \else q"
  , tcBreaks 30 "if foo then\n\
                 \  use A.X c\n\
                 \  use AA.PP.QQ e\n\
                 \  f c c e e\n\
                 \else\n\
                 \  use A.B X.d Y.d\n\
                 \  use A.B.X f\n\
                 \  g X.d X.d Y.d Y.d f f"
  , tcBreaks 30 "if foo then\n\
                 \  use A.X c\n\
                 \  f c c\n\
                 \else\n\
                 \  use A X.c YY.c\n\
                 \  g X.c X.c YY.c YY.c"
  , tcBreaks 20 "handle bar in\n\
                 \  (if foo then\n\
                 \    use A.X c\n\
                 \    f c c\n\
                 \  else\n\
                 \    use A.Y c\n\
                 \    g c c)"  -- questionable parentheses, issue #517
  , tcBreaks 28 "if foo then\n\
                 \  f (x : (∀ t. Pair t t))\n\
                 \else\n\
                 \  f (x : (∀ t. Pair t t))"
  , tcDiffRtt False "handle foo in\n\
                      \  use A x\n\
                      \  (if f x x then\n\
                      \    x\n\
                      \  else y)"  -- missing break before 'then', issue #518; surplus parentheses #517
                      "handle foo\n\
                      \in\n\
                      \  use A x\n\
                      \  (if f x x then\n\
                      \    x\n\
                      \  else y)" 15  -- parser doesn't like 'in' beginning a line
  , tcBreaks 20 "case x of\n\
                 \  () ->\n\
                 \    use A y\n\
                 \    f y y"
  , tcBreaks 12 "let\n\
                 \  use A x\n\
                 \  f x x\n\
                 \  c = g x x\n\
                 \  h x x"
  , tcBreaks 15 "handle foo in\n\
                 \  use A x\n\
                 \  f x x"
  , tcBreaks 15 "let\n\
                 \  c =\n\
                 \    use A x\n\
                 \    f x x\n\
                 \  g c"
  , tcBreaks 20 "if foo then\n\
                 \  f x x A.x A.x\n\
                 \else g"
  , tcBreaks 27 "case t of\n\
                 \  () ->\n\
                 \    a =\n\
                 \      use A B.x\n\
                 \      f B.x B.x\n\
                 \      handle foo in\n\
                 \        q =\n\
                 \          use A.B.D x\n\
                 \          h x x\n\
                 \        foo\n\
                 \    bar\n\
                 \  _ ->\n\
                 \    b =\n\
                 \      use A.C x\n\
                 \      g x x\n\
                 \    bar"
  , tcBreaks 20 "let\n\
                 \  a =\n\
                 \    handle foo in\n\
                 \      use A x\n\
                 \      f x x\n\
                 \  bar"
  , tcBreaks 16 "let\n\
                 \  a =\n\
                 \    b =\n\
                 \      use A x\n\
                 \      f x x\n\
                 \    foo\n\
                 \  bar"
  , tcBreaks 20 "let\n\
                 \  a =\n\
                 \    case x of\n\
                 \      () ->\n\
                 \        use A x\n\
                 \        f x x\n\
                 \  bar"
  , tcBreaks 20 "let\n\
                 \  a =\n\
                 \    use A x\n\
                 \    b = f x x\n\
                 \    c = g x x\n\
                 \    foo\n\
                 \  bar"
  , tcBreaks 13 "let\n\
                 \  a =\n\
                 \    use A p q r\n\
                 \    f p p\n\
                 \    f q q\n\
                 \    f r r\n\
                 \  foo"
  -- The following behaviour is possibly not ideal.  Note how the `use A B.x`
  -- would have the same effect if it was under the `c =`.  It doesn't actually
  -- need to be above the `b =`, because all the usages of A.B.X in that tree are
  -- covered by another use statement, the `use A.B x`.  Fixing this would
  -- probably require another annotation pass over the AST, to place 'candidate'
  -- use statements, to then push some of them down on the next pass.
  -- Not worth it!
  , tcBreaks 20 "let\n\
                 \  a =\n\
                 \    use A B.x\n\
                 \    b =\n\
                 \      use A.B x\n\
                 \      f x x\n\
                 \    c =\n\
                 \      g B.x B.x\n\
                 \      h A.D.x\n\
                 \    foo\n\
                 \  bar"
  , tcBreaks 80 "let\n\
                 \  use A x\n\
                 \  use A.T.A T1\n\
                 \  g = T1 +3\n\
                 \  h = T1 +4\n\
                 \  i : T -> T -> Int\n\
                 \  i p q =\n\
                 \    g' = T1 +3\n\
                 \    h' = T1 +4\n\
                 \    +2\n\
                 \  if true then x else x"
  ]
