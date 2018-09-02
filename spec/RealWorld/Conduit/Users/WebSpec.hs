module RealWorld.Conduit.Users.WebSpec
  ( spec
  ) where

import Control.Monad ((=<<))
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT(..), runExceptT)
import Data.Aeson (FromJSON, eitherDecode, encode)
import Data.ByteString.Lazy (ByteString)
import Data.Either (Either(Right))
import Data.Function (($), (.))
import Data.Functor ((<$>), void)
import Data.Semigroup ((<>))
import Data.String (String)
import Data.Text.Encoding (encodeUtf8)
import Network.HTTP.Types
  ( hAuthorization
  , status200
  , status201
  , status400
  , status401
  , status422
  )
import Network.Wai (Application)
import Network.Wai.Test (SResponse(simpleBody, simpleStatus))
import RealWorld.Conduit.Handle (Handle)
import RealWorld.Conduit.Spec.Web (withApp)
import RealWorld.Conduit.Users.Web (server, users)
import qualified RealWorld.Conduit.Users.Web.Account as Account
import RealWorld.Conduit.Users.Web.Account (Account)
import RealWorld.Conduit.Users.Web.Register (Registrant(Registrant))
import qualified RealWorld.Conduit.Web as Web
import RealWorld.Conduit.Web.Namespace (Namespace(Namespace), unNamespace)
import Servant (serveWithContext)
import Test.Hspec (Spec, around, context, describe, it, shouldBe)
import Test.Hspec.Wai.Extended (WaiSession, get', post')
import Test.Hspec.Wai.JSON (json)

app :: Handle -> Application
app handle = serveWithContext users (Web.context handle) (server handle)

decodeUserNamespace :: FromJSON a => ByteString -> Either String (Namespace "user" a)
decodeUserNamespace = eitherDecode

accountFromResponse :: SResponse -> Either String Account
accountFromResponse = (unNamespace <$>) . decodeUserNamespace . simpleBody

userNamespace :: a -> Namespace "user" a
userNamespace = Namespace

register :: Registrant -> WaiSession (Either String Account)
register =
  (accountFromResponse <$>) . post' "/api/users" [] . encode . userNamespace

spec :: Spec
spec =
  around (withApp app) $ do
    describe "POST /api/users" $ do
      context "when provided a valid body with valid values" $
        it "responds with 201 and a json encoded user response" $ do
          res <-
            post'
              "/api/users"
              []
              [json|{
                user: {
                  username: "aname",
                  email: "e@mail.com",
                  password: "secret123"
                }
              }|]
          liftIO $ do
            simpleStatus res `shouldBe` status201
            Account.username <$> accountFromResponse res `shouldBe` Right "aname"
            Account.email <$> accountFromResponse res `shouldBe` Right "e@mail.com"

      context "when provided a valid body with invalid values" $
        it "responds with 422 and a json encoded error response" $ do
          void $ register $ Registrant "secret123" "also@taken.com" "taken"
          res <-
            post'
              "/api/users"
              []
              [json|{
                user: {
                  username: "taken",
                  email: "also@taken.com",
                  password: "secret123"
                }
              }|]
          liftIO $ do
            simpleStatus res `shouldBe` status422
            simpleBody res `shouldBe`
              [json|{
                message: "Failed validation",
                errors: [
                  "EmailTaken",
                  "UsernameTaken"
                ]
              }|]

      context "when provided an invalid body" $
        it "responds with 400" $ do
          res <-
            post'
              "/api/users"
              []
              [json|{
                user: {
                  wrong: "params"
                }
              }|]
          liftIO $ do
            simpleStatus res `shouldBe` status400
            simpleBody res `shouldBe` "Error in $.user: key \"password\" not present"

    describe "POST /api/users/login" $ do
      context "when provided the correct credentials" $
        it "responds with 200 and a json encoded user response" $ do
          void $ register $ Registrant "secret123" "e@mail.com" "aname"
          res <-
            post'
              "/api/users/login"
              []
              [json|{
                user: {
                  email: "e@mail.com",
                  password: "secret123"
                }
              }|]
          liftIO $ do
            simpleStatus res `shouldBe` status200
            Account.username <$> accountFromResponse res `shouldBe` Right "aname"
            Account.email <$> accountFromResponse res `shouldBe` Right "e@mail.com"

      context "when provided incorrect credentials" $
        it "responds with a 401" $ do
          void $ register $ Registrant "secret123" "e@mail.com" "username"
          res <-
            post'
              "/api/users/login"
              []
              [json|{
                user: {
                  email: "e@mail.com",
                  password: "wrong just wrong"
                }
              }|]
          liftIO $ simpleStatus res `shouldBe` status401

    describe "GET /api/user" $ do
      context "when provided a valid token" $
        it "responds with 200 and a json encoded user response" $ do
          res <-
            runExceptT $ do
              account <-
                ExceptT $ register $ Registrant "secret123" "e@mail.com" "aname"
              lift $
                get'
                  "/api/user"
                  [(hAuthorization, encodeUtf8 ("Bearer " <> Account.token account))]
          liftIO $ do
            simpleStatus <$> res `shouldBe` Right status200
            Account.username <$>
              (accountFromResponse =<< res) `shouldBe` Right "aname"
            Account.email <$>
              (accountFromResponse =<< res) `shouldBe` Right "e@mail.com"

      context "when provided an invalid token" $
        it "responds with a 401" $ do
          res <-
            runExceptT $ do
              account <-
                ExceptT $ register $ Registrant "secret123" "e@mail.com" "aname"
              lift $
                get'
                  "/api/user"
                  [ ( hAuthorization
                    , encodeUtf8 ("Bearer " <> Account.token account <> "wrong"))
                  ]
          liftIO $ simpleStatus <$> res `shouldBe` Right status401
