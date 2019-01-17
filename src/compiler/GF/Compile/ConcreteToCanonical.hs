-- | Translate concrete syntax to canonical form
module GF.Compile.ConcreteToCanonical(concretes2canonical) where
import Data.List(nub,sort,sortBy,partition)
--import Data.Function(on)
import qualified Data.Map as M
import qualified Data.Set as S
import GF.Data.ErrM
import GF.Data.Utilities(mapSnd)
import GF.Text.Pretty
import GF.Grammar.Grammar
import GF.Grammar.Lookup(lookupFunType,lookupOrigInfo,allOrigInfos,allParamValues)
import GF.Grammar.Macros(typeForm,collectOp,collectPattOp,mkAbs,mkApp,term2patt)
import GF.Grammar.Lockfield(isLockLabel)
import GF.Grammar.Predef(cPredef,cInts)
import GF.Compile.Compute.Predef(predef)
import GF.Compile.Compute.Value(Predefined(..))
import GF.Infra.Ident(ModuleName(..),Ident,identS,prefixIdent,showIdent,isWildIdent) --,moduleNameS
--import GF.Infra.Option
import GF.Compile.Compute.ConcreteNew(normalForm,resourceValues)
import GF.Grammar.Canonical as C
import Debug.Trace

-- | Generate Canonical code for the all concrete syntaxes associated with
-- the named abstract syntax in given the grammar.
concretes2canonical opts absname gr =
  [(cncname,concrete2canonical opts gr cenv absname cnc cncmod)
     | let cenv = resourceValues opts gr,
       cnc<-allConcretes gr absname,
       let cncname = "canonical/"++render cnc ++ ".gf" :: FilePath
           Ok cncmod = lookupModule gr cnc
  ]

-- | Generate Canonical GF for the given concrete module.
-- The only options that make a difference are
-- @-haskell=noprefix@ and @-haskell=variants@.
concrete2canonical opts gr cenv absname cnc modinfo =
  Concrete (modId cnc) (modId absname)
      (neededParamTypes S.empty (params defs))
      [lincat|(_,Left lincat)<-defs]
      [lin|(_,Right lin)<-defs]
  where
    defs = concatMap (toCanonical gr absname cenv) . 
           M.toList $
           jments modinfo

    params = S.toList . S.unions . map fst

    neededParamTypes have [] = []
    neededParamTypes have (q:qs) =
        if q `S.member` have
        then neededParamTypes have qs
        else let ((got,need),def) = paramType gr q
             in def++neededParamTypes (S.union got have) (S.toList need++qs)

toCanonical gr absname cenv (name,jment) =
  case jment of
    CncCat (Just (L loc typ)) _ _ pprn _ ->
        [(pts,Left (LincatDef (gId name) (convType ntyp)))]
      where
        pts = paramTypes gr ntyp
        ntyp = nf loc typ
    CncFun (Just r@(cat,ctx,lincat)) (Just (L loc def)) pprn _ ->
        [(tts,Right (LinDef (gId name) (map gId args) (convert gr e')))]
      where
        tts = tableTypes gr [e']
--      Ok abstype = lookupFunType gr absname name
--      (absctx,_abscat,_absargs) = typeForm abstype
        e' = unAbs (length params) $
             nf loc (mkAbs params (mkApp def (map Vr args)))
        params = [(b,x)|(b,x,_)<-ctx]
        args = map snd params
--      abs_args = map (prefixIdent "abs_") args
--      lhs = [ConP (aId name) (map VarP abs_args)]
--      rhs = foldr letlin e' (zip args absctx)

    AnyInd _ m  -> case lookupOrigInfo gr (m,name) of
                     Ok (m,jment) -> toCanonical gr absname cenv (name,jment)
                     _ -> []
    _ -> []
  where
    nf loc = normalForm cenv (L loc name)
--  aId n = prefixIdent "A." (gId n)

    unAbs 0 t = t
    unAbs n (Abs _ _ t) = unAbs (n-1) t
    unAbs _ t = t


con = Cn . identS
{-
tableTypes gr ts = S.unions (map tabtys ts)
  where
    tabtys t =
      case t of
        ConcatValue v1 v2 -> S.union (tabtys v1) (tabtys v2)
        TableValue t tvs -> S.unions (paramTypes gr t:[tabtys t|TableRowValue _ t<-tvs])
        VTableValue t ts -> (S.unions (paramTypes gr t:map tabtys ts))
        Projection lv l -> tabtys lv
        Selection tv pv -> S.union (tabtys tv) (tabtys pv)
        VariantValue vs -> S.unions (map tabtys vs)
        RecordValue rvs -> S.unions [tabtys t|RecordRowValue _ t<-rvs]
        TupleValue lvs -> S.unions (map tabtys lvs)
        _ -> S.empty
-}
tableTypes gr ts = S.unions (map tabtys ts)
  where
    tabtys t =
      case t of
        V t cc -> S.union (paramTypes gr t) (tableTypes gr cc)
        T (TTyped t) cs -> S.union (paramTypes gr t) (tableTypes gr (map snd cs))
        _ -> collectOp tabtys t

paramTypes gr t =
  case t of
    RecType fs -> S.unions (map (paramTypes gr.snd) fs)
    Table t1 t2 -> S.union (paramTypes gr t1) (paramTypes gr t2)
    App tf ta -> S.union (paramTypes gr tf) (paramTypes gr ta)
    Sort _ -> S.empty
    EInt _ -> S.empty
    Q q -> lookup q
    QC q -> lookup q
    FV ts -> S.unions (map (paramTypes gr) ts)
    _ -> ignore
  where
    lookup q = case lookupOrigInfo gr q of
                 Ok (_,ResOper  _ (Just (L _ t))) ->
                                       S.insert q (paramTypes gr t)
                 Ok (_,ResParam {}) -> S.singleton q
                 _ -> ignore

    ignore = trace ("Ignore: "++show t) S.empty


{-
records ts = S.unions (map recs ts)
  where
    recs t =
      case t of
        R r -> S.insert (labels r) (records (map (snd.snd) r))
        RecType r -> S.insert (labels r) (records (map snd r))
        _ -> collectOp recs t

    labels = sort . filter (not . isLockLabel) . map fst


coerce env ty t =
  case (ty,t) of 
    (_,Let d t) -> Let d (coerce (extend env d) ty t)
    (_,FV ts) -> FV (map (coerce env ty) ts)
    (Table ti tv,V _ ts) -> V ti (map (coerce env tv) ts)
    (Table ti tv,T (TTyped _) cs) -> T (TTyped ti) (mapSnd (coerce env tv) cs)
    (RecType rt,R r) ->
      R [(l,(Just ft,coerce env ft f))|(l,(_,f))<-r,Just ft<-[lookup l rt]]
    (RecType rt,Vr x)->
      case lookup x env of
        Just ty' | ty'/=ty -> -- better to compare to normal form of ty'
          --trace ("coerce "++render ty'++" to "++render ty) $
          App (to_rcon (map fst rt)) t
        _ -> trace ("no coerce to "++render ty) t
    _ -> t
  where
    extend env (x,(Just ty,rhs)) = (x,ty):env
    extend env _ = env
-}
convert gr = convert' gr []

convert' gr vs = ppT
  where
    ppT0 = convert' gr vs
    ppTv vs' = convert' gr vs'

    ppT t =
      case t of
         -- Only for 'let' inserted on the top-level by this converter:
--      Let (x,(_,xt)) t -> let1 x (ppT0 xt) (ppT t)
--      Abs b x t -> ...
--      V ty ts -> VTableValue (convType ty) (map ppT ts)
        V ty ts -> TableValue (convType ty) [TableRowValue (ppP p) (ppT t)|(p,t)<-zip ps ts]
          where
            Ok pts = allParamValues gr ty
            Ok ps = mapM term2patt pts
        T (TTyped ty) cs -> TableValue (convType ty) (map ppCase cs)
        S t p -> selection (ppT t) (ppT p)
        C t1 t2 -> concatValue (ppT t1) (ppT t2)
        App f a -> ap (ppT f) (ppT a)
        R r -> RecordValue (fields r)
        P t l -> projection (ppT t) (lblId l)
        Vr x -> VarValue (gId x)
        Cn x -> VarValue (gId x) -- hmm
        Con c -> ParamConstant (Param (gId c) [])
        Sort k -> VarValue (gId k)
        EInt n -> IntConstant n
        Q (m,n) -> if m==cPredef then ppPredef n else VarValue (gId (qual m n))
        QC (m,n) -> ParamConstant (Param (gId (qual m n)) [])
        K s -> StrConstant s
        Empty -> StrConstant ""
        FV ts -> VariantValue (map ppT ts)
        Alts t' vs -> alts vs (ppT t')
        _ -> error $ "convert' "++show t

    ppCase (p,t) = TableRowValue (ppP p) (ppTv (patVars p++vs) t)

    ppPredef n =
      case predef n of
        Ok BIND       -> c "Predef.BIND"
        Ok SOFT_BIND  -> c "Predef.SOFT_BIND"
        Ok SOFT_SPACE -> c "Predef.SOFT_SPACE"
        Ok CAPIT      -> c "Predef.CAPIT"
        Ok ALL_CAPIT  -> c "Predef.ALL_CAPIT"
        _ -> VarValue (gId n)

    ppP p =
      case p of
        PC c ps -> ParamPattern (Param (gId c) (map ppP ps))
        PP (m,c) ps -> ParamPattern (Param (gId (qual m c)) (map ppP ps))
        PR r -> RecordPattern (fields r) {-
        PW -> WildPattern
        PV x -> VarP x
        PString s -> Lit (show s) -- !!
        PInt i -> Lit (show i)
        PFloat x -> Lit (show x)
        PT _ p -> ppP p
        PAs x p -> AsP x (ppP p) -}
      where
        fields = map field . filter (not.isLockLabel.fst)
        field (l,p) = RecordRow (lblId l) (ppP p)

--  patToParam p = case ppP p of ParamPattern pv -> pv

--  token s = single (c "TK" `Ap` lit s)

    alts vs = PreValue (map alt vs)
      where
        alt (t,p) = (pre p,ppT0 t)

        pre (K s) = [s]
        pre (Strs ts) = concatMap pre ts
        pre (EPatt p) = pat p
        pre t = error $ "pre "++show t

        pat (PString s) = [s]
        pat (PAlt p1 p2) = pat p1++pat p2
        pat p = error $ "pat "++show p

    fields = map field . filter (not.isLockLabel.fst)
    field (l,(_,t)) = RecordRow (lblId l) (ppT t)
  --c = Const
    c = VarValue . VarValueId
    lit s = c (show s) -- hmm

    ap f a = case f of
               ParamConstant (Param p ps) ->
                 ParamConstant (Param p (ps++[a]))
               _ -> error $ "convert' ap: "++render (ppA f <+> ppA a)

    join = id

--  empty = if va then List [] else c "error" `Ap` c (show "empty variant")
--  variants = if va then \ ts -> join' (List (map ppT ts))
--                   else \ (t:_) -> ppT t
{-
    aps f [] = f
    aps f (a:as) = aps (ap f a) as

    dedup ts =
        if M.null dups
        then List (map ppT ts)
        else Lets [(ev i,ppT t)|(i,t)<-defs] (List (zipWith entry ts is))
      where
        entry t i = maybe (ppT t) (Var . ev) (M.lookup i dups)
        ev i = identS ("e'"++show i)

        defs = [(i1,t)|(t,i1:_:_)<-ms]
        dups = M.fromList [(i2,i1)|(_,i1:is@(_:_))<-ms,i2<-i1:is]
        ms = M.toList m
        m = fmap sort (M.fromListWith (++) (zip ts [[i]|i<-is]))
        is = [0..]::[Int]
-}

concatValue v1 v2 =
  case (v1,v2) of
    (StrConstant "",_) -> v2
    (_,StrConstant "") -> v1
    _ -> ConcatValue v1 v2

projection r l = maybe (Projection r l) id (proj r l)

proj r l =
  case r of
    RecordValue r -> case [v|RecordRow l' v<-r,l'==l] of
                          [v] -> Just v
                          _ -> Nothing
    _ -> Nothing

selection t v =
  case t of
    TableValue tt r ->
        case nub [rv|TableRowValue _ rv<-keep] of
          [rv] -> rv
          _ -> Selection (TableValue tt r') v
      where
        r' = if null discard
             then r
             else keep++[TableRowValue WildPattern impossible]
        (keep,discard) = partition (mightMatchRow v) r
    _ -> Selection t v

impossible = ErrorValue "impossible"

mightMatchRow v (TableRowValue p _) =
  case p of
    WildPattern -> True
    _ -> mightMatch v p

mightMatch v p =
  case v of
    ConcatValue _ _ -> False
    ParamConstant (Param c1 pvs) ->
      case p of
        ParamPattern (Param c2 pps) -> c1==c2 && length pvs==length pps &&
                                       and [mightMatch v p|(v,p)<-zip pvs pps]
        _ -> False
    RecordValue rv ->
      case p of
        RecordPattern rp ->
          and [maybe False (flip mightMatch p) (proj v l) | RecordRow l p<-rp]
        _ -> False
    _ -> True

patVars p =
  case p of
    PV x -> [x]
    PAs x p -> x:patVars p
    _ -> collectPattOp patVars p

convType = ppT
  where
    ppT t =
      case t of
        Table ti tv -> TableType (ppT ti) (ppT tv)
        RecType rt -> RecordType (convFields rt)
--      App tf ta -> TAp (ppT tf) (ppT ta)
--      FV [] -> tcon0 (identS "({-empty variant-})")
        Sort k -> convSort k
--      EInt n -> tcon0 (identS ("({-"++show n++"-})")) -- type level numeric literal
        FV (t:ts) -> ppT t -- !!
        QC (m,n) -> ParamType (ParamTypeId (gId (qual m n)))
        Q (m,n) -> ParamType (ParamTypeId (gId (qual m n)))
        _ -> error $ "Missing case in convType for: "++show t

    convFields = map convField . filter (not.isLockLabel.fst)
    convField (l,r) = RecordRow (lblId l) (ppT r)

    convSort k = case showIdent k of
                   "Float" -> FloatType
                   "Int" -> IntType
                   "Str" -> StrType
                   _ -> error ("convSort "++show k)

toParamType t = case convType t of
                  ParamType pt -> pt
                  _ -> error ("toParamType "++show t)

toParamId t = case toParamType t of
                   ParamTypeId p -> p

paramType gr q@(_,n) =
    case lookupOrigInfo gr q of
      Ok (m,ResParam (Just (L _ ps)) _)
       {- - | m/=cPredef && m/=moduleNameS "Prelude"-} ->
         ((S.singleton (m,n),argTypes ps),
          [ParamDef name (map (param m) ps)]
         )
       where name = gId (qual m n)
      Ok (m,ResOper  _ (Just (L _ t)))
        | m==cPredef && n==cInts ->
           ((S.empty,S.empty),[]) {-
           ((S.singleton (m,n),S.empty),
            [Type (ConAp (gId (qual m n)) [identS "n"]) (TId (identS "Int"))])-}
        | otherwise ->
           ((S.singleton (m,n),paramTypes gr t),
            [ParamAliasDef (gId (qual m n)) (convType t)])
      _ -> ((S.empty,S.empty),[])
  where
    param m (n,ctx) = Param (gId (qual m n)) [toParamId t|(_,_,t)<-ctx]
    argTypes = S.unions . map argTypes1
    argTypes1 (n,ctx) = S.unions [paramTypes gr t|(_,_,t)<-ctx]

qual :: ModuleName -> Ident -> Ident
qual m = prefixIdent (render m++"_")


lblId = LabelId . render -- hmm
modId (MN m) = ModId (showIdent m)

class FromIdent i where gId :: Ident -> i

instance FromIdent VarId where
  gId i = if isWildIdent i then Anonymous else VarId (showIdent i)

instance FromIdent C.FunId where gId = C.FunId . showIdent
instance FromIdent CatId where gId = CatId . showIdent
instance FromIdent ParamId where gId = ParamId . showIdent
instance FromIdent VarValueId where gId = VarValueId . showIdent
