{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

{-# OPTIONS -Wno-orphans #-}

import Data.Text qualified as Text
import Network.HTTP.Client.TLS (newTlsManager)
import Network.Stellar.Keypair (decodePublicKey)
import Options.Applicative (maybeReader)
import Options.Applicative.Types (readerAsk)
import Options.Generic (Generic, ParseField, ParseFields, ParseRecord,
                        getRecord)
import Options.Generic qualified
import Servant.Client (ClientError (FailureResponse), ClientM, mkClientEnv,
                       runClientM)
import System.Exit (exitFailure)
import System.IO (stderr)
import Text.Pretty.Simple (pHPrint, pPrint)

import Stellar.Horizon.Client (Address (Address), Asset, TransactionOnChain,
                               assetFromText, getAccount, getAccountOffers,
                               getAccountOperations, getAccountTransactionsDto,
                               getAccountsList, getFeeStats, publicServerBase,
                               transactionFromDto)
import Stellar.Horizon.DTO (Offer, Operation, Record (Record),
                            Records (Records))
import Stellar.Horizon.DTO qualified

instance ParseField Address where
    readField = maybeReader $ (\t -> Address t <$ decodePublicKey t) . Text.pack

instance ParseFields Address
instance ParseRecord Address

instance ParseField Asset where
    readField = assetFromText . Text.pack <$> readerAsk

instance ParseFields Asset
instance ParseRecord Asset

data Input
    = Account Address
    | Accounts{asset :: Asset}
    | Fee_stats
    | Offers        {account :: Address}
    | Operations    {account :: Address}
    | Transactions  {account :: Address}
    deriving (Generic)

instance ParseRecord Input

cli :: Input -> ClientM ()
cli = \case
    Account account         -> getAccount account               >>= pPrint
    Accounts{asset}         -> getAccountsList asset            >>= pPrint
    Fee_stats               -> getFeeStats                      >>= pPrint
    Offers      {account}   -> getAccountOffers'       account  >>= pPrint
    Operations  {account}   -> getAccountOperations'   account  >>= pPrint
    Transactions{account}   -> getAccountTransactions' account  >>= pPrint

getAccountOffers' :: Address -> ClientM [Offer]
getAccountOffers' account = do
    Records records <- getAccountOffers account Nothing Nothing
    pure $ map (\Record{value} -> value) records

getAccountOperations' :: Address -> ClientM [Operation]
getAccountOperations' account = do
    Records records <- getAccountOperations account Nothing Nothing Nothing
    pure $ map (\Record{value} -> value) records

getAccountTransactions' :: Address -> ClientM [TransactionOnChain]
getAccountTransactions' account = do
    Records records <- getAccountTransactionsDto account Nothing Nothing
    pure $ map (\Record{value} -> transactionFromDto value) records

main :: IO ()
main = do
    manager <- newTlsManager
    input <- getRecord "Stellar Horizon client"
    res <- runClientM (cli input) $ mkClientEnv manager publicServerBase
    case res of
        Left (FailureResponse _ response) -> do
            putStrLn "FailureResponse"
            pHPrint stderr response
            exitFailure
        Left err -> do
            pHPrint stderr err
            exitFailure
        Right () -> pure ()
