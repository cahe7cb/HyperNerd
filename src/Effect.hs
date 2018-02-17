module Effect ( Effect
              , EffectF (..)
              , say
              , logMsg
              , createEntity
              , getEntityById
              , getRandomEntity
              , now
              ) where

import Control.Monad.Free
import qualified Data.Text as T
import Data.Time
import Entity

data EffectF s = Say T.Text s
               | LogMsg T.Text s
               | CreateEntity T.Text Properties (Entity -> s)
               | GetEntityById T.Text Int (Maybe Entity -> s)
               | GetRandomEntity T.Text (Maybe Entity -> s)
               | Now (UTCTime -> s)

instance Functor EffectF where
    fmap f (Say msg s) = Say msg (f s)
    fmap f (LogMsg msg s) = LogMsg msg (f s)
    fmap f (CreateEntity name properties h) =
        CreateEntity name properties (f . h)
    fmap f (GetEntityById name ident h) =
        GetEntityById name ident (f . h)
    fmap f (GetRandomEntity name h) =
        GetRandomEntity name (f . h)
    fmap f (Now h) = Now (f . h)

type Effect = Free EffectF

say :: T.Text -> Effect ()
say msg = liftF $ Say msg ()

logMsg :: T.Text -> Effect ()
logMsg msg = liftF $ LogMsg msg ()

createEntity :: T.Text -> Properties -> Effect Entity
createEntity name properties = liftF $ CreateEntity name properties id

getEntityById :: T.Text -> Int -> Effect (Maybe Entity)
getEntityById name ident = liftF $ GetEntityById name ident id

getRandomEntity :: T.Text -> Effect (Maybe Entity)
getRandomEntity name = liftF $ GetRandomEntity name id

now :: Effect UTCTime
now = liftF $ Now id