{-# LANGUAGE BangPatterns, CPP, ScopedTypeVariables #-}
module Happstack.Server.Internal.Listen(listen, listen',listenOn,listenOnIP) where

import Happstack.Server.Internal.Types          (Conf(..), Request, Response)
import Happstack.Server.Internal.Handler        (request)
import Happstack.Server.Internal.Socket         (acceptLite)
import Happstack.Server.Internal.TimeoutManager (cancel, initialize, register, forceTimeoutAll)
import Happstack.Server.Internal.TimeoutSocket  as TS
import qualified Control.Concurrent.Thread.Group as TG
import Control.Exception.Extensible             as E
import Control.Concurrent                       (forkIO, killThread, myThreadId)
import Control.Monad
import qualified Data.Maybe as Maybe
import Network.BSD                              (getProtocolNumber)
import qualified Network.Socket                 as Socket
import System.IO.Error                          (isFullError)
{-
#ifndef mingw32_HOST_OS
-}
import System.Posix.Signals
{-
#endif
-}
import System.Log.Logger (Priority(..), logM)
import Util ((<₪>), altMap)

log':: Priority -> String -> IO ()
log' = logM "Happstack.Server.HTTP.Listen"


listenOn :: Int -> IO Socket.Socket
listenOn portm = do
    proto <- getProtocolNumber "tcp"
    E.bracketOnError
        (Socket.socket Socket.AF_INET6 Socket.Stream proto)
        (Socket.close) $ \ sock -> sock <$ do
      Socket.setSocketOption sock Socket.ReuseAddr 1
      Socket.bind sock (Socket.SockAddrInet (fromIntegral portm) iNADDR_ANY)
      Socket.listen sock (Socket.maxListenQueue)

listenOnIP :: String  -- ^ IP address to listen on (must be an IP address not a host name)
           -> Int     -- ^ port number to listen on
           -> IO Socket.Socket
listenOnIP ip portm = do
    proto <- getProtocolNumber "tcp"
    sockAddr <- inet_addr ip <₪> \ case
        Left hostAddr -> Socket.SockAddrInet portm' hostAddr
        Right (hostAddr, flowInfo, scopeId) -> Socket.SockAddrInet6 portm' flowInfo hostAddr scopeId
    E.bracketOnError
        (Socket.socket Socket.AF_INET6 Socket.Stream proto)
        (Socket.close) $ \ sock -> sock <$ do
        Socket.setSocketOption sock Socket.ReuseAddr 1
        Socket.bind sock sockAddr
        Socket.listen sock (max 1024 Socket.maxListenQueue)
  where portm' = fromIntegral portm

inet_addr :: String -> IO (Either Socket.HostAddress (Socket.HostAddress6, Socket.FlowInfo, Socket.ScopeID))
inet_addr ip = do
  addrInfos <- Socket.getAddrInfo (Just Socket.defaultHints) (Just ip) Nothing
  let getHostAddress addrInfo = case Socket.addrAddress addrInfo of
        Socket.SockAddrInet _ hostAddress -> Just (Left hostAddress)
        Socket.SockAddrInet6 _ flowInfo hostAddress scopeId -> Just (Right (hostAddress, flowInfo, scopeId))
        _ -> Nothing
  maybe (fail "inet_addr: no HostAddress") pure $ altMap getHostAddress addrInfos

iNADDR_ANY :: Socket.HostAddress
iNADDR_ANY = 0

-- | Bind and listen port
listen :: Conf -> (Request -> IO Response) -> IO ()
listen conf hand = do
    let port' = port conf
    lsocket <- listenOn port'
    Socket.setSocketOption lsocket Socket.KeepAlive 1
    listen' lsocket conf hand

-- | Use a previously bind port and listen
listen' :: Socket.Socket -> Conf -> (Request -> IO Response) -> IO ()
listen' s conf hand = do
{-
#ifndef mingw32_HOST_OS
-}
  void $ installHandler openEndedPipe Ignore Nothing
{-
#endif
-}
  let port' = port conf
      fork = case threadGroup conf of
               Nothing -> forkIO
               Just tg -> \m -> fst `liftM` TG.forkIO tg m
  tm <- initialize ((timeout conf) * (10^(6 :: Int)))
  -- http:// loop
  log' NOTICE ("Listening for http:// on port " ++ show port')
  let eh (x::SomeException) = when ((fromException x) /= Just ThreadKilled) $ log' ERROR ("HTTP request failed with: " ++ show x)
      work (sock, hn, p) =
          do tid <- myThreadId
             thandle <- register tm (killThread tid)
             let timeoutIO = TS.timeoutSocketIO thandle sock
             request timeoutIO (logAccess conf) (hn,fromIntegral p) hand `E.catch` eh
             -- remove thread from timeout table
             cancel thandle
             Socket.close sock
      loop = forever $ do w <- acceptLite s
                          fork $ work w
      pe e = log' ERROR ("ERROR in http accept thread: " ++ show e)
      infi :: IO ()
      infi = loop `catchSome` pe >> infi

  infi `finally` (Socket.close s >> forceTimeoutAll tm)

{--
#ifndef mingw32_HOST_OS
-}
  void $ installHandler openEndedPipe Ignore Nothing
{-
#endif
-}
  where  -- why are these handlers needed?

    catchSome op h = op `E.catches` [
            Handler $ \(e :: ArithException) -> h (toException e),
            Handler $ \(e :: ArrayException) -> h (toException e),
            Handler $ \(e :: IOException)    ->
                if isFullError e
                   then return () -- h (toException e) -- we could log the exception, but there could be thousands of them
                   else throw e
          ]
