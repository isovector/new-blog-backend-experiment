{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

import Development.Shake
import Development.Shake.FilePath
import Development.Shake.Util

import Data.Text (Text, pack)
import qualified Data.Text.IO as TIO
import qualified Data.Text.Lazy.IO as TLIO

import Text.Pandoc (readOrg, writeHtml5, runPure, def, handleError)

import System.Directory
import Data.Time.Clock

import Text.Hamlet

import Text.Blaze.Html.Renderer.Text

data Route = Index
           | Page Text
           | Post Text
           | Css Text

data SiteConfig = SiteConfig { siteTitle :: String }

data PageConfig = PageConfig { pageTitle :: Maybe String
                             , pageMtime :: Maybe UTCTime
                             }

siteConfig :: SiteConfig
siteConfig = SiteConfig { siteTitle = "rational irrationality" }

render :: Route -> [(Text, Text)] -> Text
render Index _ =  "/index.html"
render (Page s) _ = "/pages/" <> s <> ".html"
render (Post s) _ = "/posts/" <> s <> ".html"
render (Css s) _ = "/css/" <> s <> ".css"

indexTemplate :: FilePath
indexTemplate = "templates/index.html"

frameTemplate :: FilePath
frameTemplate = "templates/frame.html"

frame ::  PageConfig -> [String] -> Html -> HtmlUrl Route
frame pageConfig pages body = $(hamletFile "templates/frame.html")

index :: [(String, UTCTime)] -> HtmlUrl Route
index posts = $(hamletFile "templates/index.html")

main :: IO ()
main = shakeArgs shakeOptions $ do
    let site = "site"
    let templates = "templates"

    let strip a b = case stripExtension "org" a of
            Nothing -> b
            Just x -> x : b

    pages <- liftIO $ foldr strip [] <$> (listDirectory "pages")
    liftIO $ print $ pages
    posts <- liftIO $ foldr strip [] <$> (listDirectory "posts")

    want $ map (\page -> site </> "pages" </> page <.> "html") pages
    want $ map (\post -> site </> "posts" </> post <.> "html") posts
    want [site </> "index" <.> "html"]

    site </> "index" <.> "html" %> \out -> do
        need [indexTemplate, frameTemplate]
        posts' <- liftIO $ mapM (\post -> do
            time <- getModificationTime $ "posts" </> post <.> "org"
            return (post, time)
            ) posts
        let body = index posts' render
        let html = frame (PageConfig { pageTitle = Nothing
                                    , pageMtime = Nothing
                                    }) pages body render
        liftIO $ TLIO.writeFile out $ renderHtml html

    [ site </> "pages" </> "*.html", site </> "posts" </> "*.html"] |%> \out -> do
        let base = dropExtension $ dropDirectory1 out
        let inp = base <.> "org"

        need [inp, frameTemplate]
        liftIO $ do
            mtime <- getModificationTime inp
            org <- TIO.readFile inp
            let result = runPure $ do
                  doc <- readOrg def org
                  writeHtml5 def doc
            html <- handleError result
            TLIO.writeFile out $ renderHtml $ frame (PageConfig { pageTitle = Just $ dropDirectory1 base
                                                                , pageMtime = Just mtime
                                                                }) pages html render
