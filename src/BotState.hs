{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module BotState
  ( advanceTimeouts
  , handleInEvent
  , withBotState
  , withBotState'
  , newBotState
  , destroyTimeoutsOfChannel
  , BotState(..)
  , TransportState(..)
  ) where

import Bot
import Config
import Control.Concurrent.STM
import Control.Exception
import Control.Monad.Free
import Control.Monad.Trans.Class
import Control.Monad.Trans.Maybe
import Data.Foldable
import Data.Function
import Data.List
import Data.Maybe
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time
import qualified Database.SQLite.Simple as SQLite
import Effect
import Markov
import Network.HTTP.Simple
import qualified Network.URI.Encode as URI
import qualified Sqlite.EntityPersistence as SEP
import System.IO
import Text.InterpolatedString.QM
import Text.Printf
import Transport

data TransportState
  = TwitchTransportState { tsTwitchConfig :: TwitchConfig
                         , tsIncoming :: IncomingQueue
                         , tsOutcoming :: OutcomingQueue }
  | DiscordTransportState { tsDiscordConfig :: DiscordConfig
                          , tsIncoming :: IncomingQueue
                          , tsOutcoming :: OutcomingQueue }

data Timeout = Timeout { timeoutDuration :: Integer
                       , timeoutChannel :: Maybe Channel
                       , timeoutEffect :: Effect ()
                       }

data BotState = BotState
  { bsTransports :: [TransportState]
  -- Shared
  , bsTimeouts :: [Timeout]
  , bsSqliteConn :: SQLite.Connection
  , bsConfig :: Config
  , bsMarkovPath :: Maybe FilePath
  , bsMarkov :: Maybe Markov
  }

destroyTimeoutsOfChannel :: BotState -> Maybe Channel -> BotState
destroyTimeoutsOfChannel botState channel =
  botState
    {bsTimeouts = filter ((/= channel) . timeoutChannel) $ bsTimeouts botState}

newTwitchTransportState :: TwitchConfig -> IO TransportState
newTwitchTransportState config = do
  incoming <- atomically newTQueue
  outcoming <- atomically newTQueue
  return
    TwitchTransportState
      {tsIncoming = incoming, tsOutcoming = outcoming, tsTwitchConfig = config}

newDiscordTransportState :: DiscordConfig -> IO TransportState
newDiscordTransportState config = do
  incoming <- atomically newTQueue
  outcoming <- atomically newTQueue
  return
    DiscordTransportState
      {tsIncoming = incoming, tsOutcoming = outcoming, tsDiscordConfig = config}

newBotState :: Maybe FilePath -> Config -> SQLite.Connection -> IO BotState
newBotState markovPath conf sqliteConn = do
  transports <-
    catMaybes <$>
    sequence
      [ sequence (newTwitchTransportState <$> configTwitch conf)
      , sequence (newDiscordTransportState <$> configDiscord conf)
      ]
  markov <- runMaybeT (MaybeT (return markovPath) >>= lift . loadMarkov)
  return
    BotState
      { bsSqliteConn = sqliteConn
      , bsTimeouts = []
      , bsMarkovPath = markovPath
      , bsMarkov = markov
      , bsTransports = transports
      , bsConfig = conf
      }

withBotState' ::
     Maybe FilePath -> Config -> FilePath -> (BotState -> IO ()) -> IO ()
withBotState' markovPath conf databasePath block =
  SQLite.withConnection databasePath $ \sqliteConn -> do
    SEP.prepareSchema sqliteConn
    newBotState markovPath conf sqliteConn >>= block

withBotState ::
     Maybe FilePath -> FilePath -> FilePath -> (BotState -> IO ()) -> IO ()
withBotState markovPath tcPath databasePath block = do
  conf <- configFromFile tcPath
  withBotState' markovPath conf databasePath block

twitchCmdEscape :: T.Text -> T.Text
twitchCmdEscape = T.dropWhile (`elem` ['/', '.']) . T.strip

channelsOfState :: TransportState -> [Channel]
channelsOfState channelState =
  case channelState of
    TwitchTransportState {tsTwitchConfig = param} ->
      return $ TwitchChannel $ tcChannel param
    DiscordTransportState {tsDiscordConfig = param} ->
      map (DiscordChannel . fromIntegral) $ dcChannels param

stateOfChannel :: BotState -> Channel -> Maybe TransportState
stateOfChannel botState channel =
  find (elem channel . channelsOfState) $ bsTransports botState

applyEffect :: (BotState, Effect ()) -> IO (BotState, Effect ())
applyEffect self@(_, Pure _) = return self
applyEffect (botState, Free (Say channel text s)) = do
  case stateOfChannel botState channel of
    Just channelState ->
      case channelState of
        TwitchTransportState {} ->
          atomically $
          writeTQueue (tsOutcoming channelState) $
          OutMsg channel (twitchCmdEscape text)
        _ ->
          atomically $
          writeTQueue (tsOutcoming channelState) $ OutMsg channel text
    Nothing -> hPutStrLn stderr [qms|[ERROR] Channel does not exist {channel} |]
  return (botState, s)
applyEffect (botState, Free (LogMsg msg s)) = do
  putStrLn $ T.unpack msg
  return (botState, s)
applyEffect (botState, Free (Now s)) = do
  timestamp <- getCurrentTime
  return (botState, s timestamp)
applyEffect (botState, Free (ErrorEff msg)) = do
  putStrLn $ printf "[ERROR] %s" msg
  return (botState, Pure ())
applyEffect (botState, Free (CreateEntity name properties s)) = do
  entityId <- SEP.createEntity (bsSqliteConn botState) name properties
  return (botState, s entityId)
applyEffect (botState, Free (GetEntityById name entityId s)) = do
  entity <- SEP.getEntityById (bsSqliteConn botState) name entityId
  return (botState, s entity)
applyEffect (botState, Free (DeleteEntityById name entityId s)) = do
  SEP.deleteEntityById (bsSqliteConn botState) name entityId
  return (botState, s)
applyEffect (botState, Free (UpdateEntityById entity s)) = do
  entity' <- SEP.updateEntityById (bsSqliteConn botState) entity
  return (botState, s entity')
applyEffect (botState, Free (SelectEntities name selector s)) = do
  entities <- SEP.selectEntities (bsSqliteConn botState) name selector
  return (botState, s entities)
applyEffect (botState, Free (DeleteEntities name selector s)) = do
  n <- SEP.deleteEntities (bsSqliteConn botState) name selector
  return (botState, s n)
applyEffect (botState, Free (HttpRequest request s)) = do
  response <-
    catch
      (Just <$> httpLBS request)
      (\e -> do
         hPutStrLn
           stderr
           [qms|[ERROR] HTTP request failed:
                {e :: HttpException}|]
         return Nothing)
  case response of
    Just response' -> return (botState, s response')
    Nothing -> return (botState, Pure ())
applyEffect (botState, Free (TwitchApiRequest request s)) =
  case configTwitch $ bsConfig botState of
    Just TwitchConfig {tcTwitchClientId = clientId} -> do
      response <-
        httpLBS (addRequestHeader "Client-ID" (TE.encodeUtf8 clientId) request)
      return (botState, s response)
    Nothing -> do
      hPutStrLn
        stderr
        [qms|[ERROR] Bot tried to perform Twitch API request.
             But Twitch clientId is not setup.|]
      return (botState, Pure ())
applyEffect (botState, Free (GitHubApiRequest request s)) = do
  let githubConfig = configGithub $ bsConfig botState
  case githubConfig of
    Just GithubConfig {githubApiKey = apiKey} -> do
      response <-
        httpLBS
          (addRequestHeader "User-Agent" "HyperNerd" $
           addRequestHeader "Authorization" [qms|token {apiKey}|] request)
      return (botState, s response)
    Nothing -> do
      hPutStrLn
        stderr
        [qms|[ERROR] Bot tried to do GitHub API request.
             But GitHub API key is not setup.|]
      return (botState, Pure ())
applyEffect (botState, Free (TimeoutEff ms e c s)) =
  return ((botState {bsTimeouts = Timeout ms e c : bsTimeouts botState}), s)
applyEffect (botState, Free (Listen effect s)) = do
  (botState', sayLog) <- listenEffectIO applyEffect (botState, effect)
  return (botState', s sayLog)
applyEffect (botState, Free (TwitchCommand channel name args s)) =
  case stateOfChannel botState channel of
    Just channelState -> do
      atomically $
        writeTQueue (tsOutcoming channelState) $
        OutMsg channel [qms|/{name} {T.concat $ intersperse " " args}|]
      return (botState, s)
    Nothing -> do
      hPutStrLn stderr [qms|[ERROR] Channel does not exist {channel} |]
      return (botState, Pure ())
applyEffect (botState, Free (RandomMarkov s)) = do
  let markov = MaybeT $ return $ bsMarkov botState
  sentence <- runMaybeT (eventsAsText <$> (markov >>= lift . simulate))
  return (botState, s sentence)
applyEffect (botState, Free (ReloadMarkov s)) = do
  markov <-
    runMaybeT (MaybeT (return $ bsMarkovPath botState) >>= lift . loadMarkov)
  return (botState {bsMarkov = markov}, s ("Reloaded the model" <$ markov))
applyEffect (botState, Free (GetVar _ s)) = return (botState, s Nothing)
applyEffect (botState, Free (CallFun "urlencode" [text] s)) =
  return (botState, s $ Just $ T.pack $ URI.encode $ T.unpack text)
applyEffect (botState, Free (CallFun _ _ s)) = return (botState, s Nothing)

runEffectIO :: ((a, Effect ()) -> IO (a, Effect ())) -> (a, Effect ()) -> IO a
runEffectIO _ (x, Pure _) = return x
runEffectIO f effect = f effect >>= runEffectIO f

listenEffectIO ::
     ((a, Effect ()) -> IO (a, Effect ())) -> (a, Effect ()) -> IO (a, [T.Text])
listenEffectIO _ (x, Pure _) = return (x, [])
listenEffectIO f (x, Free (Say _ text s)) = do
  (x', sayLog) <- listenEffectIO f (x, s)
  return (x', text : sayLog)
listenEffectIO f effect = f effect >>= listenEffectIO f

runEffectTransIO :: BotState -> Effect () -> IO BotState
runEffectTransIO botState effect =
  SQLite.withTransaction (bsSqliteConn botState) $
  runEffectIO applyEffect (botState, effect)

advanceTimeout :: Integer -> Timeout -> Timeout
advanceTimeout dt (Timeout t c e) = Timeout (t - dt) c e

advanceTimeouts :: Integer -> BotState -> IO BotState
advanceTimeouts dt botState =
  foldlM runEffectTransIO (botState {bsTimeouts = unripe}) $
  map timeoutEffect ripe
  where
    (ripe, unripe) =
      span ((<= 0) . timeoutDuration) $
      sortBy (compare `on` timeoutDuration) $
      map (advanceTimeout dt) $ bsTimeouts botState

handleInEvent :: Bot -> InEvent -> BotState -> IO BotState
handleInEvent b event botState = runEffectTransIO botState $ b event
