module Lookup where

import Operations
import Abstract
import Modules

import List (nub)
import Monad

-- lookup in resource and concrete in compiling; for abstract, use Look

lookupResDef :: SourceGrammar -> Ident -> Ident -> Err Term
lookupResDef gr = look True where 
  look isTop m c = do
    mi   <- lookupModule gr m
    case mi of
      ModMod mo -> do
        info <- lookupInfo mo c
        case info of
          ResOper _ (Yes t) -> return $ qualifAnnot m t 
          ResOper _ Nope    -> return (Q m c) ---- if isTop then lookExt m c 
                                 ---- else prtBad "cannot find in exts" c 
          AnyInd _ n        -> look False n c
          ResParam _        -> return $ QC m c
          ResValue _        -> return $ QC m c
          _   -> Bad $ prt c +++ "is not defined in resource" +++ prt m
      _ -> Bad $ prt m +++ "is not a resource"
  lookExt m c =
    checks ([look False n c | n <- allExtensions gr m] ++ [return (Q m c)])

lookupResType :: SourceGrammar -> Ident -> Ident -> Err Type
lookupResType gr m c = do
  mi   <- lookupModule gr m
  case mi of
    ModMod mo -> do
      info <- lookupInfo mo c
      case info of
        ResOper (Yes t) _ -> return $ qualifAnnot m t
        ResOper (May n) _ -> lookupResType gr n c
        AnyInd _ n        -> lookupResType gr n c
        ResParam _        -> return $ typePType
        ResValue (Yes t)  -> return $ qualifAnnotPar m t
        _   -> Bad $ prt c +++ "has no type defined in resource" +++ prt m
    _ -> Bad $ prt m +++ "is not a resource"

lookupParams :: SourceGrammar -> Ident -> Ident -> Err [Param]
lookupParams gr = look True where 
  look isTop m c = do
    mi   <- lookupModule gr m
    case mi of
      ModMod mo -> do
        info <- lookupInfo mo c
        case info of
          ResParam (Yes ps) -> return ps
          ---- ResParam   Nope   -> if isTop then lookExt m c 
          ----                       else prtBad "cannot find params in exts" c 
          AnyInd _ n        -> look False n c
          _   -> Bad $ prt c +++ "has no parameters defined in resource" +++ prt m
      _ -> Bad $ prt m +++ "is not a resource"
  lookExt m c =
    checks [look False n c | n <- allExtensions gr m]

lookupParamValues :: SourceGrammar -> Ident -> Ident -> Err [Term]
lookupParamValues gr m c = do
  ps <- lookupParams gr m c
  liftM concat $ mapM mkPar ps
 where
   mkPar (f,co) = do
     vs <- liftM combinations $ mapM (\ (_,ty) -> allParamValues gr ty) co
     return $ map (mkApp (QC m f)) vs

lookupFirstTag :: SourceGrammar -> Ident -> Ident -> Err Term
lookupFirstTag gr m c = do
  vs <- lookupParamValues gr m c
  case vs of
    v:_ -> return v
    _ -> prtBad "no parameter values given to type" c

allParamValues :: SourceGrammar -> Type -> Err [Term]
allParamValues cnc ptyp = case ptyp of
     QC p c -> lookupParamValues cnc p c
     RecType r -> do
       let (ls,tys) = unzip r
       tss <- mapM allPV tys
       return [R (zipAssign ls ts) | ts <- combinations tss]
     _ -> prtBad "cannot find parameter values for" ptyp
  where
    allPV = allParamValues cnc

qualifAnnot :: Ident -> Term -> Term
qualifAnnot _ = id
-- Using this we wouldn't have to annotate constants defined in a module itself.
-- But things are simpler if we do (cf. Zinc).
-- Change Rename.self2status to change this behaviour.

-- we need this for lookup in ResVal
qualifAnnotPar m t = case t of
  Cn c  -> Q m c
  Con c -> QC m c
  _ -> composSafeOp (qualifAnnotPar m) t


lookupLincat :: SourceGrammar -> Ident -> Ident -> Err Type
lookupLincat gr m c | elem c [zIdent "String", zIdent "Int"] = 
  return defLinType --- ad hoc; not needed?

lookupLincat gr m c = do
  mi <- lookupModule gr m
  case mi of
    ModMod mo -> do
      info <- lookupInfo mo c
      case info of
        CncCat (Yes t) _ _ -> return t
        AnyInd _ n         -> lookupLincat gr n c
        _   -> Bad $ prt c +++ "has no linearization type in" +++ prt m
    _ -> Bad $ prt m +++ "is not concrete"


opersForType :: SourceGrammar -> Type -> [(QIdent,Term)]
opersForType gr val = 
  [((i,f),ty) | (i,m) <- allModMod gr, 
                (f,ResOper (Yes ty) _) <- tree2list $ jments m,
                Ok valt <- [valTypeCnc ty],
                valt == val
  ]
