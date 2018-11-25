module RealWorld.Conduit.Articles.Database.Article.AttributesSpec
  ( spec
  ) where

import Database.Beam (primaryKey)
import RealWorld.Conduit.Articles.Database (create)
import RealWorld.Conduit.Articles.Database.Article.Attributes
  ( Attributes(Attributes)
  , ValidationFailure(BodyRequired, DescriptionRequired,
                  TitleWouldProduceDuplicateSlug)
  )
import qualified RealWorld.Conduit.Articles.Database.Article.Attributes as Attributes
import RealWorld.Conduit.Spec.Database (withConnection)
import qualified RealWorld.Conduit.Users.Database as User
import qualified RealWorld.Conduit.Users.Database.User.Attributes as UserAttributes
import Test.Hspec (Spec, around, describe, it, shouldBe)

userCreateParams :: UserAttributes.Attributes Identity
userCreateParams =
  UserAttributes.Attributes
    { UserAttributes.password = "password123"
    , UserAttributes.email = "user@example.com"
    , UserAttributes.username = "Username"
    , UserAttributes.bio = ""
    , UserAttributes.image = Nothing
    }

createParams :: Attributes Identity
createParams =
  Attributes
    { Attributes.slug = "slug"
    , Attributes.title = "Title"
    , Attributes.description = "Description"
    , Attributes.body = "Body"
    }

spec :: Spec
spec =
  around withConnection $ do
    describe "forInsert" $ do
      it "returns an Attributes Identity when valid" $ \conn -> do
        attributes <-
          runExceptT $
          Attributes.forInsert
            conn
            "Title"
            "Description"
            "Body"
        Attributes.slug <$> attributes `shouldBe` Right "title"
        Attributes.title <$> attributes `shouldBe` Right "Title"
        Attributes.description <$> attributes `shouldBe` Right "Description"
        Attributes.body <$> attributes `shouldBe` Right "Body"

      it "returns a validation failure when title is taken" $ \conn -> do
        user <- User.create conn userCreateParams
        void $
          create
            conn
            (primaryKey user)
            createParams
              {Attributes.title = "Taken", Attributes.slug = "taken"}
        attributes <-
          runExceptT $
          Attributes.forInsert
            conn
            "Taken"
            "Description"
            "Body"
        Attributes.title <$> attributes `shouldBe` Left [TitleWouldProduceDuplicateSlug "taken"]

      it "returns a validation failure when description is absent" $ \conn -> do
        attributes <- runExceptT $ Attributes.forInsert conn "Title" "" "Body"
        Attributes.title <$> attributes `shouldBe` Left [DescriptionRequired]

      it "returns a validation failure when body is absent" $ \conn -> do
        attributes <- runExceptT $ Attributes.forInsert conn "Title" "Description" ""
        Attributes.title <$> attributes `shouldBe` Left [BodyRequired]

    describe "forUpdate" $ do
      it "returns an Attributes Maybe when valid" $ \conn -> do
        user <- User.create conn userCreateParams
        article <- create conn (primaryKey user) createParams
        attributes <-
          runExceptT $
          Attributes.forUpdate
            conn
            article
            (Just "Title")
            (Just "A description")
            (Just "A body")
        Attributes.slug <$> attributes `shouldBe` Right (Just "title")
        Attributes.title <$> attributes `shouldBe` Right (Just "Title")
        Attributes.body <$> attributes `shouldBe` Right (Just "A body")

      it "returns a validation failure when title is taken" $ \conn -> do
        user <- User.create conn userCreateParams
        article <- create conn (primaryKey user) createParams
        void $
          create
            conn
            (primaryKey user)
            createParams
              {Attributes.title = "Taken", Attributes.slug = "taken"}
        attributes <-
          runExceptT $
          Attributes.forUpdate
            conn
            article
            (Just "Taken")
            Nothing
            Nothing
        Attributes.title <$> attributes `shouldBe` Left [TitleWouldProduceDuplicateSlug "taken"]

      it "returns a validation failure when description is absent" $ \conn -> do
        user <- User.create conn userCreateParams
        article <- create conn (primaryKey user) createParams
        attributes <-
          runExceptT $ Attributes.forUpdate conn article Nothing (Just "") Nothing
        Attributes.title <$> attributes `shouldBe` Left [DescriptionRequired]

      it "returns a validation failure when body is absent" $ \conn -> do
        user <- User.create conn userCreateParams
        article <- create conn (primaryKey user) createParams
        attributes <-
          runExceptT $ Attributes.forUpdate conn article Nothing Nothing (Just "")
        Attributes.title <$> attributes `shouldBe` Left [BodyRequired]