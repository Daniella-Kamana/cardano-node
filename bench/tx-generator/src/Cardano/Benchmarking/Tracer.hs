{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PackageImports #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

{-# OPTIONS_GHC -Wno-all-missed-specialisations #-}
{-# OPTIONS_GHC -Wno-unticked-promoted-constructors #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Cardano.Benchmarking.Tracer
  ( initDefaultTracers
  ) where

import           "contra-tracer" Control.Tracer (Tracer (..))
import           GHC.Generics

import           Data.Aeson as A
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Map as Map

import           Data.Text (Text)
import qualified Data.Text as Text

import           Cardano.Api
import           Cardano.Logging

import           Cardano.Benchmarking.LogTypes
import           Cardano.Benchmarking.Types

generatorTracer :: LogFormatting a => (a -> Namespace) -> Text -> Trace IO FormattedMessage -> IO (Trace IO a)
generatorTracer namesFor tracerName tr = do
  tr'   <- machineFormatter Nothing tr
  tr''  <- withDetailsFromConfig tr'
  pure $ withNamesAppended namesFor
          $ appendName tracerName
              tr''

initDefaultTracers :: IO BenchTracers
initDefaultTracers = do
  st <-  standardTracer
  benchTracer <-  generatorTracer genericNames "benchmark" st
  configureTracers initialTraceConfig benchTracerDocumented [benchTracer]
  n2nSubmitTracer <- generatorTracer genericNames "submitN2N" st
  configureTracers initialTraceConfig nodeToNodeSubmissionTraceDocumented [n2nSubmitTracer]
  connectTracer <- generatorTracer genericNames "connect" st
  configureTracers initialTraceConfig sendRecvConnectDocumented [connectTracer]
  submitTracer <- generatorTracer namesForSubmission2 "submit" st
  configureTracers initialTraceConfig submission2Documented [submitTracer]

  return $ BenchTracers
    { btTxSubmit_    = Tracer (traceWith benchTracer)
    , btConnect_     = Tracer (traceWith connectTracer)
    , btSubmission2_ = Tracer (traceWith submitTracer)
    , btN2N_         = Tracer (traceWith n2nSubmitTracer)
    }

initialTraceConfig :: TraceConfig
initialTraceConfig = TraceConfig {
      tcOptions = Map.fromList
          [ ([], [ConfSeverity (SeverityF Nothing)])
          , initConf "benchmark"
          , initConf "submitN2N"
          , initConf "connect"
          , initConf "submit"
          , (["llSubmit"], [ConfDetail DMinimal])
          ]
    , tcForwarder = defaultForwarder
    , tcNodeName = Nothing
    , tcPeerFrequency = Just 2000 -- Every 2 seconds
    , tcResourceFrequency = Just 1000 -- Every second
    }
  where
    initConf :: Text -> (Namespace, [ConfigOption])
    initConf tr = ([tr], [ConfDetail DMaximum])

genericNames :: (ConstructorName f, Generic a, Rep a ~ D1 c f) => a ->  [Text]
genericNames x = [ Text.pack $ constructorName $ unM1 $ from x ]

class ConstructorName f where
  constructorName :: f p -> String

instance (ConstructorName f, ConstructorName g) => ConstructorName (f :+: g) where
  constructorName (L1 x) = constructorName x
  constructorName (R1 x) = constructorName x
instance (Constructor ('MetaCons n f r)) => ConstructorName (C1 ('MetaCons n f r) x) where
  constructorName = conName

instance LogFormatting (TraceBenchTxSubmit TxId) where
  forHuman = Text.pack . show
  forMachine DMinimal _ = mempty
  forMachine DNormal t = case t of
    TraceBenchTxSubRecv _      -> mconcat ["kind" .= A.String "TraceBenchTxSubRecv"]
    TraceBenchTxSubStart _     -> mconcat ["kind" .= A.String "TraceBenchTxSubStart"]
    TraceBenchTxSubServAnn _   -> mconcat ["kind" .= A.String "TraceBenchTxSubServAnn"]
    TraceBenchTxSubServReq _   -> mconcat ["kind" .= A.String "TraceBenchTxSubServReq"]
    TraceBenchTxSubServAck _   -> mconcat ["kind" .= A.String "TraceBenchTxSubServAck"]
    TraceBenchTxSubServDrop _  -> mconcat ["kind" .= A.String "TraceBenchTxSubServDrop"]
    TraceBenchTxSubServOuts _  -> mconcat ["kind" .= A.String "TraceBenchTxSubServOuts"]
    TraceBenchTxSubServUnav _  -> mconcat ["kind" .= A.String "TraceBenchTxSubServUnav"]
    TraceBenchTxSubServFed _ _ -> mconcat ["kind" .= A.String "TraceBenchTxSubServFed"]
    TraceBenchTxSubServCons _  -> mconcat ["kind" .= A.String "TraceBenchTxSubServCons"]
    TraceBenchTxSubIdle        -> mconcat ["kind" .= A.String "TraceBenchTxSubIdle"]
    TraceBenchTxSubRateLimit _ -> mconcat ["kind" .= A.String "TraceBenchTxSubRateLimit"]
    TraceBenchTxSubSummary _   -> mconcat ["kind" .= A.String "TraceBenchTxSubSummary"]
    TraceBenchTxSubDebug _     -> mconcat ["kind" .= A.String "TraceBenchTxSubDebug"]
    TraceBenchTxSubError _     -> mconcat ["kind" .= A.String "TraceBenchTxSubError"]
  forMachine DDetailed t = forMachine DMaximum t
  forMachine DMaximum t = case t of
    TraceBenchTxSubRecv txIds ->
      mconcat [ "kind"  .= A.String "TraceBenchTxSubRecv"
              , "txIds" .= toJSON txIds
              ]
    TraceBenchTxSubStart txIds ->
      mconcat [ "kind"  .= A.String "TraceBenchTxSubStart"
              , "txIds" .= toJSON txIds
              ]
    TraceBenchTxSubServAnn txIds ->
      mconcat [ "kind"  .= A.String "TraceBenchTxSubServAnn"
              , "txIds" .= toJSON txIds
              ]
    TraceBenchTxSubServReq txIds ->
      mconcat [ "kind"  .= A.String "TraceBenchTxSubServReq"
              , "txIds" .= toJSON txIds
              ]
    TraceBenchTxSubServAck txIds ->
      mconcat [ "kind"  .= A.String "TraceBenchTxSubServAck"
              , "txIds" .= toJSON txIds
              ]
    TraceBenchTxSubServDrop txIds ->
      mconcat [ "kind"  .= A.String "TraceBenchTxSubServDrop"
              , "txIds" .= toJSON txIds
              ]
    TraceBenchTxSubServOuts txIds ->
      mconcat [ "kind"  .= A.String "TraceBenchTxSubServOuts"
              , "txIds" .= toJSON txIds
              ]
    TraceBenchTxSubServUnav txIds ->
      mconcat [ "kind"  .= A.String "TraceBenchTxSubServUnav"
              , "txIds" .= toJSON txIds
              ]
    TraceBenchTxSubServFed txIds ix ->
      mconcat [ "kind"  .= A.String "TraceBenchTxSubServFed"
              , "txIds" .= toJSON txIds
              , "index" .= toJSON ix
              ]
    TraceBenchTxSubServCons txIds ->
      mconcat [ "kind"  .= A.String "TraceBenchTxSubServCons"
              , "txIds" .= toJSON txIds
              ]
    TraceBenchTxSubIdle ->
      mconcat [ "kind" .= A.String "TraceBenchTxSubIdle"
              ]
    TraceBenchTxSubRateLimit limit ->
      mconcat [ "kind"  .= A.String "TraceBenchTxSubRateLimit"
              , "limit" .= toJSON limit
              ]
    TraceBenchTxSubSummary summary ->
      mconcat [ "kind"    .= A.String "TraceBenchTxSubSummary"
              , "summary" .= toJSON summary
              ]
    TraceBenchTxSubDebug s ->
      mconcat [ "kind" .= A.String "TraceBenchTxSubDebug"
              , "msg"  .= A.String (Text.pack s)
              ]
    TraceBenchTxSubError s ->
      mconcat [ "kind" .= A.String "TraceBenchTxSubError"
              , "msg"  .= A.String s
              ]

benchTracerDocumented :: Documented (TraceBenchTxSubmit TxId)
benchTracerDocumented = Documented
  [ emptyDoc ["benchmark", "TraceBenchTxSubRecv"]
  , emptyDoc ["benchmark", "TraceBenchTxSubStart"]
  , emptyDoc ["benchmark", "TraceBenchTxSubServAnn"]
  , emptyDoc ["benchmark", "TraceBenchTxSubServReq"]
  , emptyDoc ["benchmark", "TraceBenchTxSubServAck"]
  , emptyDoc ["benchmark", "TraceBenchTxSubServDrop"]
  , emptyDoc ["benchmark", "TraceBenchTxSubServOuts"]
  , emptyDoc ["benchmark", "TraceBenchTxSubServUnav"]
  , emptyDoc ["benchmark", "TraceBenchTxSubServFed"]
  , emptyDoc ["benchmark", "TraceBenchTxSubServCons"]
  , emptyDoc ["benchmark", "TraceBenchTxSubIdle"]
  , emptyDoc ["benchmark", "TraceBenchTxSubRateLimit"]
  , emptyDoc ["benchmark", "TraceBenchTxSubServCons"]
  , emptyDoc ["benchmark", "TraceBenchTxSubIdle"]
  , emptyDoc ["benchmark", "TraceBenchTxSubRateLimit"]
  , emptyDoc ["benchmark", "TraceBenchTxSubSummary"]
  , emptyDoc ["benchmark", "TraceBenchTxSubDebug"]
  , emptyDoc ["benchmark", "TraceBenchTxSubError"]
  ]


instance LogFormatting NodeToNodeSubmissionTrace where
  forHuman = Text.pack . show
  forMachine _verb = \case
    ReqIdsBlocking (Ack ack) (Req req) -> KeyMap.fromList
      [ "kind" .= A.String "ReqIdsBlocking"
      , "ack"  .= A.toJSON ack
      , "req"  .= A.toJSON req ]
    IdsListBlocking sent -> KeyMap.fromList
      [ "kind" .= A.String "IdsListBlocking"
      , "sent" .= A.toJSON sent ]
    ReqIdsPrompt (Ack ack) (Req req) -> KeyMap.fromList
      [ "kind" .= A.String "ReqIdsPrompt"
      , "ack"  .= A.toJSON ack
      , "req"  .= A.toJSON req ]
    IdsListPrompt sent -> KeyMap.fromList
      [ "kind" .= A.String "IdsListPrompt"
      , "sent" .= A.toJSON sent ]
    EndOfProtocol -> KeyMap.fromList [ "kind" .= A.String "EndOfProtocol" ]
    ReqTxs req -> KeyMap.fromList
       [ "kind" .= A.String "ReqTxs"
       , "req"  .= A.toJSON req ]
    TxList sent -> KeyMap.fromList
       [ "kind" .= A.String "TxList"
       , "sent" .= A.toJSON sent ]

nodeToNodeSubmissionTraceDocumented :: Documented NodeToNodeSubmissionTrace
nodeToNodeSubmissionTraceDocumented = Documented
  [ emptyDoc ["submitN2N", "ReqIdsBlocking"]
  , emptyDoc ["submitN2N", "IdsListBlocking"]
  , emptyDoc ["submitN2N", "ReqIdsPrompt"]
  , emptyDoc ["submitN2N", "IdsListPrompt"]
  , emptyDoc ["submitN2N", "ReqTxs"]
  , emptyDoc ["submitN2N", "TxList"]
  ]

instance LogFormatting SendRecvConnect where
  forHuman = Text.pack . show
  forMachine _ _ = KeyMap.fromList [ "kind" .= A.String "SendRecvConnect" ]


sendRecvConnectDocumented :: Documented SendRecvConnect
sendRecvConnectDocumented = Documented
  [ emptyDoc ["connect"]
  ]

instance LogFormatting SendRecvTxSubmission2 where
  forHuman = Text.pack . show
  forMachine _ _ = KeyMap.fromList [ "kind" .= A.String "SendRecvTxSubmission2" ]

namesForSubmission2 :: SendRecvTxSubmission2 ->  [Text]
namesForSubmission2 _ = []

submission2Documented :: Documented SendRecvTxSubmission2
submission2Documented = Documented
  [ emptyDoc ["submission2"]
  ]

emptyDoc :: Namespace -> DocMsg a
emptyDoc ns = DocMsg ns [] "ToDo: write benchmark tracer docs"
