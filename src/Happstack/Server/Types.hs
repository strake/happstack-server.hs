module Happstack.Server.Types
    (Request(..), Response(..), RqBody(..), Input(..), HeaderPair(..),
     takeRequestBody,
     rqURL, mkHeaders,
     getHeader, getHeaderBS, getHeaderUnsafe,
     hasHeader, hasHeaderBS, hasHeaderUnsafe,
     setHeader, setHeaderBS, setHeaderUnsafe,
     addHeader, addHeaderBS, addHeaderUnsafe,
     setRsCode, -- setCookie, setCookies,
     Conf(..), nullConf, result, resultBS,
     redirect, -- redirect_, redirect', redirect'_,
     isHTTP1_0, isHTTP1_1,
     RsFlags(..), nullRsFlags, noContentLength,
     Version(..), Length(..), Method(..), Headers, continueHTTP,
     Host, ContentType(..)
    ) where

import Happstack.Server.Internal.Types
