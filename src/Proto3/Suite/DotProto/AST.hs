-- | Fairly straightforward AST encoding of the .proto grammar

{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE RecordWildCards            #-}

module Proto3.Suite.DotProto.AST
  ( -- * Types
      MessageName(..)
    , FieldName(..)
    , PackageName(..)
    , DotProtoIdentifier(..)
    , DotProtoImport(..)
    , DotProtoImportQualifier(..)
    , DotProtoPackageSpec(..)
    , DotProtoOption(..)
    , DotProtoDefinition(..)
    , DotProtoMeta(..)
    , DotProto(..)
    , DotProtoValue(..)
    , DotProtoPrimType(..)
    , Packing(..)
    , Path(..), fakePath
    , DotProtoType(..)
    , DotProtoEnumValue
    , DotProtoEnumPart(..)
    , Streaming(..)
    , DotProtoServicePart(..)
    , RPCMethod(..)
    , DotProtoMessagePart(..)
    , DotProtoField(..)
    , DotProtoReservedField(..)
  ) where

import           Control.Applicative
import           Control.Monad
import           Data.Int                  (Int32)
import qualified Data.List.NonEmpty        as NE
import           Data.String               (IsString)
import           Numeric.Natural
import           Prelude                   hiding (FilePath)
import           Proto3.Wire.Types         (FieldNumber (..))
import           Test.QuickCheck
import           Test.QuickCheck.Instances ()
import           Turtle                    (FilePath)

-- | The name of a message
newtype MessageName = MessageName
  { getMessageName :: String
  } deriving (Eq, Ord, IsString)

instance Show MessageName where
  show = show . getMessageName

-- | The name of some field
newtype FieldName = FieldName
  { getFieldName :: String
  } deriving (Eq, Ord, IsString)

instance Show FieldName where
  show = show . getFieldName

-- | The name of the package
newtype PackageName = PackageName
  { getPackageName :: String
  } deriving (Eq, Ord, IsString)

instance Show PackageName where
  show = show . getPackageName

newtype Path = Path { components :: NE.NonEmpty String } deriving (Show, Eq, Ord)

-- Used for testing
fakePath :: Path
fakePath = Path ("fakePath" NE.:| [])

data DotProtoIdentifier
  = Single String
  | Dots   Path
  | Qualified DotProtoIdentifier DotProtoIdentifier
  | Anonymous -- [recheck] is there a better way to represent unnamed things
  deriving (Show, Eq, Ord)

-- | Top-level import declaration
data DotProtoImport = DotProtoImport
  { dotProtoImportQualifier :: DotProtoImportQualifier
  , dotProtoImportPath      :: FilePath
  } deriving (Show, Eq, Ord)

instance Arbitrary DotProtoImport where
    arbitrary = do
      dotProtoImportQualifier <- arbitrary
      let dotProtoImportPath = mempty
      return (DotProtoImport {..})

data DotProtoImportQualifier
  = DotProtoImportPublic
  | DotProtoImportWeak
  | DotProtoImportDefault
  deriving (Show, Eq, Ord)

instance Arbitrary DotProtoImportQualifier where
  arbitrary = elements
    [ DotProtoImportDefault
    , DotProtoImportWeak
    , DotProtoImportPublic
    ]

-- | The namespace declaration
data DotProtoPackageSpec
  = DotProtoPackageSpec DotProtoIdentifier
  | DotProtoNoPackage
  deriving (Show, Eq)

instance Arbitrary DotProtoPackageSpec where
  arbitrary = oneof
    [ return DotProtoNoPackage
    , fmap DotProtoPackageSpec arbitrarySingleIdentifier
    , fmap DotProtoPackageSpec arbitraryPathIdentifier
    ]

-- | An option id/value pair, can be attached to many types of statements
data DotProtoOption = DotProtoOption
  { dotProtoOptionIdentifier :: DotProtoIdentifier
  , dotProtoOptionValue      :: DotProtoValue
  } deriving (Show, Eq, Ord)

instance Arbitrary DotProtoOption where
    arbitrary = do
      dotProtoOptionIdentifier <- oneof
        [ arbitraryPathIdentifier
        , arbitraryNestedIdentifier
        ]
      dotProtoOptionValue <- arbitrary
      return (DotProtoOption {..})

-- | Top-level protocol definitions
data DotProtoDefinition
  = DotProtoMessage String DotProtoIdentifier [DotProtoMessagePart]
  | DotProtoEnum    String DotProtoIdentifier [DotProtoEnumPart]
  | DotProtoService String DotProtoIdentifier [DotProtoServicePart]
  deriving (Show, Eq)


instance Arbitrary DotProtoDefinition where
  arbitrary = oneof [arbitraryMessage, arbitraryEnum]
    where
      arbitraryMessage = do
        comment    <- pure mempty  -- until parser supports comments
        identifier <- arbitrarySingleIdentifier
        parts      <- smallListOf arbitrary
        return (DotProtoMessage comment identifier parts)

      arbitraryEnum = do
        comment    <- pure mempty  -- until parser supports comments
        identifier <- arbitrarySingleIdentifier
        parts      <- smallListOf arbitrary
        return (DotProtoEnum comment identifier parts)

-- | Tracks misc metadata about the AST
data DotProtoMeta = DotProtoMeta
  { metaModulePath :: Path
    -- ^ The "module path" associated with the .proto file from which this AST
    -- was parsed. The "module path" is derived from the `--includeDir`-relative
    -- .proto filename passed to 'parseProtoFile'. See
    -- 'Proto3.Suite.DotProto.Internal.toModulePath' for details on how module
    -- path values are constructed. See
    -- 'Proto3.Suite.DotProto.Generate.modulePathModName' to see how it is used
    -- during code generation.
  } deriving (Show, Eq)

instance Arbitrary DotProtoMeta where
  arbitrary = pure (DotProtoMeta fakePath)

-- | This data structure represents a .proto file
--   The actual source order of protobuf statements isn't meaningful so
--   statements are sorted by type during parsing.
--   A .proto file with more than one package declaration is considered invalid.
data DotProto = DotProto
  { protoImports     :: [DotProtoImport]
  , protoOptions     :: [DotProtoOption]
  , protoPackage     :: DotProtoPackageSpec
  , protoDefinitions :: [DotProtoDefinition]
  , protoMeta        :: DotProtoMeta
  } deriving (Show, Eq)

instance Arbitrary DotProto where
  arbitrary = do
    protoImports     <- smallListOf arbitrary
    protoOptions     <- smallListOf arbitrary
    protoPackage     <- arbitrary
    protoDefinitions <- smallListOf arbitrary
    protoMeta        <- arbitrary
    return (DotProto {..})

-- | Matches the definition of `constant` in the proto3 language spec
--   These are only used as rvalues
data DotProtoValue
  = Identifier DotProtoIdentifier
  | StringLit  String
  | IntLit     Int
  | FloatLit   Double
  | BoolLit    Bool
  deriving (Show, Eq, Ord)

instance Arbitrary DotProtoValue where
  arbitrary = oneof
    [ fmap Identifier  arbitrarySingleIdentifier
    , fmap StringLit  (return "")
    , fmap IntLit      arbitrary
    , fmap FloatLit    arbitrary
    , fmap BoolLit     arbitrary
    ]

data DotProtoPrimType
  = Int32
  | Int64
  | SInt32
  | SInt64
  | UInt32
  | UInt64
  | Fixed32
  | Fixed64
  | SFixed32
  | SFixed64
  | String
  | Bytes
  | Bool
  | Float
  | Double
  | Named DotProtoIdentifier
  -- ^ A named type, referring to another message or enum defined in the same file
  deriving (Show, Eq)

instance Arbitrary DotProtoPrimType where
  arbitrary = oneof
    [ elements
      [ Int32
      , Int64
      , SInt32
      , SInt64
      , UInt32
      , UInt64
      , Fixed32
      , Fixed64
      , SFixed32
      , SFixed64
      , String
      , Bytes
      , Bool
      , Float
      , Double
      ]
    , fmap Named arbitrarySingleIdentifier
    ]

data Packing
  = PackedField
  | UnpackedField
  deriving (Show, Eq)

instance Arbitrary Packing where
  arbitrary = elements [PackedField, UnpackedField]

-- | This type is an almagamation of the modifiers used in types.
--   It corresponds to a syntax role but not a semantic role, not all modifiers
--   are meaningful in every type context.
data DotProtoType
  = Prim           DotProtoPrimType
  | Repeated       DotProtoPrimType
  | NestedRepeated DotProtoPrimType
  | Map            DotProtoPrimType DotProtoPrimType
  deriving (Show, Eq)

instance Arbitrary DotProtoType where
  arbitrary = oneof [fmap Prim arbitrary]

type DotProtoEnumValue = Int32

data DotProtoEnumPart
  = DotProtoEnumField DotProtoIdentifier DotProtoEnumValue [DotProtoOption]
  | DotProtoEnumOption DotProtoOption
  | DotProtoEnumEmpty
  deriving (Show, Eq)

instance Arbitrary DotProtoEnumPart where
  arbitrary = oneof [arbitraryField, arbitraryOption]
    where
      arbitraryField = do
        identifier <- arbitraryIdentifier
        enumValue  <- arbitrary
        opts       <- arbitrary
        return (DotProtoEnumField identifier enumValue opts)

      arbitraryOption = do
        option <- arbitrary
        return (DotProtoEnumOption option)

data Streaming
  = Streaming
  | NonStreaming
  deriving (Show, Eq)

instance Arbitrary Streaming where
  arbitrary = elements [Streaming, NonStreaming]

data DotProtoServicePart
  = DotProtoServiceRPCMethod RPCMethod
  | DotProtoServiceOption DotProtoOption
  | DotProtoServiceEmpty
  deriving (Show, Eq)

instance Arbitrary DotProtoServicePart where
  arbitrary = oneof
    [ DotProtoServiceRPCMethod <$> arbitrary
    , DotProtoServiceOption <$> arbitrary
    ]

data RPCMethod = RPCMethod
  { rpcMethodName :: DotProtoIdentifier
  , rpcMethodRequestType :: DotProtoIdentifier
  , rpcMethodRequestStreaming :: Streaming
  , rpcMethodResponseType :: DotProtoIdentifier
  , rpcMethodResponseStreaming :: Streaming
  , rpcMethodOptions :: [DotProtoOption]
  } deriving (Show, Eq)

instance Arbitrary RPCMethod where
  arbitrary = do
    rpcMethodName <- arbitrarySingleIdentifier
    rpcMethodRequestType <- arbitraryIdentifier
    rpcMethodRequestStreaming  <- arbitrary
    rpcMethodResponseType <- arbitraryIdentifier
    rpcMethodResponseStreaming  <- arbitrary
    rpcMethodOptions <- smallListOf arbitrary
    return RPCMethod{..}

data DotProtoMessagePart
  = DotProtoMessageField DotProtoField
  | DotProtoMessageOneOf DotProtoIdentifier [DotProtoField]
  | DotProtoMessageDefinition DotProtoDefinition
  | DotProtoMessageReserved   [DotProtoReservedField]
  | DotProtoMessageOption DotProtoOption
  deriving (Show, Eq)

instance Arbitrary DotProtoMessagePart where
  arbitrary = oneof
    [ arbitraryField
    , arbitraryOneOf
    , arbitraryDefinition
    , arbitraryReserved
    ]
    where
      arbitraryField = do
        field <- arbitrary
        return (DotProtoMessageField field)

      arbitraryOneOf = do
        name   <- arbitrarySingleIdentifier
        fields <- smallListOf arbitrary
        return (DotProtoMessageOneOf name fields)

      arbitraryDefinition = do
        definition <- arbitrary
        return (DotProtoMessageDefinition definition)

      arbitraryReserved = do
        fields <- oneof [smallListOf1 arbitrary, arbitraryReservedLabels]
        return (DotProtoMessageReserved fields)

      arbitraryReservedLabels :: Gen [DotProtoReservedField]
      arbitraryReservedLabels = smallListOf1 (ReservedIdentifier <$> return "")

data DotProtoField = DotProtoField
  { dotProtoFieldNumber  :: FieldNumber
  , dotProtoFieldType    :: DotProtoType
  , dotProtoFieldName    :: DotProtoIdentifier
  , dotProtoFieldOptions :: [DotProtoOption]
  , dotProtoFieldComment :: String
  }
  | DotProtoEmptyField
  deriving (Show, Eq)

instance Arbitrary DotProtoField where
  arbitrary = do
    dotProtoFieldNumber  <- arbitrary
    dotProtoFieldType    <- arbitrary
    dotProtoFieldName    <- arbitraryIdentifier
    dotProtoFieldOptions <- smallListOf arbitrary
    -- TODO: Generate random comments once the parser supports comments
    dotProtoFieldComment <- pure mempty
    return (DotProtoField {..})

data DotProtoReservedField
  = SingleField Int
  | FieldRange  Int Int
  | ReservedIdentifier String
  deriving (Show, Eq)

instance Arbitrary DotProtoReservedField where
  arbitrary =
    oneof [arbitrarySingleField, arbitraryFieldRange]
      where
        arbitraryFieldNumber = do
          natural <- arbitrary
          return (fromIntegral (natural :: Natural))

        arbitrarySingleField = do
          fieldNumber <- arbitraryFieldNumber
          return (SingleField fieldNumber)

        arbitraryFieldRange = do
          begin <- arbitraryFieldNumber
          end   <- arbitraryFieldNumber
          return (FieldRange begin end)

--------------------------------------------------------------------------------
-- | QC Arbitrary instance for generating random protobuf

_arbitraryService :: Gen DotProtoDefinition
_arbitraryService = do
  comment    <- pure mempty  -- until parser supports comments
  identifier <- arbitrarySingleIdentifier
  parts      <- smallListOf arbitrary
  return (DotProtoService comment identifier parts)

arbitraryIdentifierName :: Gen String
arbitraryIdentifierName = do
  c  <- elements (['a'..'z'] ++ ['A'..'Z'])
  cs <- smallListOf (elements (['a'..'z'] ++ ['A'..'Z'] ++ ['_']))
  return (c:cs)

arbitrarySingleIdentifier :: Gen DotProtoIdentifier
arbitrarySingleIdentifier = fmap Single arbitraryIdentifierName

arbitraryPathIdentifier :: Gen DotProtoIdentifier
arbitraryPathIdentifier = do
  name  <- arbitraryIdentifierName
  names <- smallListOf1 arbitraryIdentifierName
  pure . Dots . Path $ name NE.:| names

arbitraryNestedIdentifier :: Gen DotProtoIdentifier
arbitraryNestedIdentifier = do
  identifier0 <- arbitraryIdentifier
  identifier1 <- arbitrarySingleIdentifier
  return (Qualified identifier0 identifier1)

-- these two kinds of identifiers are usually interchangeable, the others are not
arbitraryIdentifier :: Gen DotProtoIdentifier
arbitraryIdentifier = oneof [arbitrarySingleIdentifier, arbitraryPathIdentifier]

-- [note] quickcheck's default scaling generates *extremely* large asts past 20 iterations
--        the parser is not particularly slow but it does have noticeable delay on megabyte-large .proto files
smallListOf :: Gen a -> Gen [a]
smallListOf x = choose (0, 5) >>= \n -> vectorOf n x

smallListOf1 :: Gen a -> Gen [a]
smallListOf1 x = choose (1, 5) >>= \n -> vectorOf n x
