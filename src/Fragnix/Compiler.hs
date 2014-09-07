module Fragnix.Compiler where

import Fragnix.Slice
import Fragnix.Nest 

import Prelude hiding (writeFile)

import Language.Haskell.Exts.Syntax (
    Module(Module),ModuleName(ModuleName),ModulePragma(LanguagePragma),
    Name(Ident),ImportDecl(ImportDecl),ImportSpec(IVar,IAbs))
import Language.Haskell.Exts.SrcLoc (noLoc)
import Language.Haskell.Exts.Parser (parseDecl,fromParseResult)
import Language.Haskell.Exts.Pretty (prettyPrint)

import Data.Text.IO (writeFile)
import Data.Text (pack,unpack)

import System.FilePath ((</>),(<.>))
import System.Directory (createDirectoryIfMissing)
import System.Process (rawSystem)

import Control.Monad (forM_)

assemble :: Slice -> Module
assemble (Slice sliceID slice usages) =
    let decl = fromParseResult . parseDecl . unpack
        decls = case slice of
            Binding signature body -> [decl signature,decl body]
        modulName = ModuleName (sliceModuleName sliceID)
        pragmas = [LanguagePragma noLoc [Ident "NoImplicitPrelude"]]
        imports = map usageImport usages
    in Module noLoc modulName pragmas Nothing Nothing imports decls

usageImport :: Usage -> ImportDecl
usageImport (Usage maybeQualification usedName symbolSource) =
    let modulName = case symbolSource of
            OtherSlice sliceID -> ModuleName (sliceModuleName sliceID)
            Primitive originalModule -> ModuleName (unpack originalModule)
        qualified = maybe False (const True) maybeQualification
        maybeAlias = fmap (ModuleName . unpack) maybeQualification
        importSpec = case usedName of
            Variable name -> IVar name
            Abstract name -> IAbs name
    in ImportDecl noLoc modulName qualified False Nothing maybeAlias (Just (False,[importSpec]))

slicePath :: SliceID -> FilePath
slicePath sliceID = "fragnix" </> sliceFileName sliceID

sliceFileName :: SliceID -> FilePath
sliceFileName sliceID = sliceModuleName sliceID <.> "hs"

sliceModuleName :: SliceID -> String
sliceModuleName sliceID = "F" ++ show sliceID

assembleTransitive :: SliceID -> IO ()
assembleTransitive sliceID = do
    slice <- get sliceID
    forM_ (usedSlices slice) compile
    writeFile (slicePath sliceID) (pack (prettyPrint (assemble slice)))

compile :: SliceID -> IO ()
compile sliceID = do
    createDirectoryIfMissing True "fragnix"
    assembleTransitive sliceID
    rawSystem "ghc" ["-o","main","-ifragnix","-main-is",sliceModuleName 0,slicePath 0] >>= print

usedSlices :: Slice -> [SliceID]
usedSlices (Slice _ _ usages) = [sliceID | Usage _ _ (OtherSlice sliceID) <- usages]
