{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Bot.FridayTest
  ( spec
  ) where

import Bot.Friday (containsYtLink, ytLinkId)
import Test.HUnit
import Text.InterpolatedString.QM

containsYtLinkTest :: Test
containsYtLinkTest =
  TestLabel "Text Contains YouTube Link" $
  TestList $
  map
    (\(input, expected) ->
       TestCase $
       assertEqual [qms|Does `{input}` contain a YouTube link?|] expected $
       containsYtLink input)
    [ ("https://www.youtube.com/watch?v=SbY6QI8c4k8", True)
    , ("http://www.youtube.com/watch?v=SbY6QI8c4k8", True)
    , ("http://youtube.com/watch?v=SbY6QI8c4k8", True)
    , ("https://www.youtube.com/watch?v=SbY6QI8c4k8&t=8s", True)
    , ( "https://www.youtube.com/watch?v=SbY6QI8c4k8&t=8s pls watch this thx"
      , True)
    , ( "pls watch this https://www.youtube.com/watch?v=SbY6QI8c4k8&t=8s thx"
      , True)
    , ("https://youtu.be/SbY6QI8c4k8", True)
    , ("https://www.youtube.com/watch?v=", False)
    , ("", False)
    , ("youtube.com hello", False)
    , ("youtu.be/SbY6QI8c4k8", False)
    , ("youtube.com/watch?v=SbY6QI8c4k8", False)
    , ("https://twitch.tv/tsoding", False)
    ]

ytLinkIdTest :: Test
ytLinkIdTest =
  TestLabel "Extracting YouTube video ID from the text" $
  TestList $
  map
    (\(input, expected) ->
       TestCase $
       assertEqual [qms|Does `{input}` have YouTube id `{expected}`?|] expected $
       ytLinkId input)
    [ ("https://www.youtube.com/watch?v=etMJxBigrc", Just "etMJxBigrc")
    -- TODO(#669): ytLinkIdTest is failing
    -- , ("https://www.youtube.com/watch?v=etMJxB-igrc", Just "etMJxB-igrc")
    ]

spec :: Test
spec = TestList [containsYtLinkTest, ytLinkIdTest]
