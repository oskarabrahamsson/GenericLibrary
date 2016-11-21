{-# LANGUAGE GADTs #-}
module GCM (GCM, output, link, createPort, createParameter, component, fun, compileGCM) where 
import Control.Monad.Writer
import Control.Monad.State.Lazy
import Port
import Program
import CP

-- A GRACeFUL concept map command
data GCMCommand a where
    Output     :: (CPType a) => Port a -> String  -> GCMCommand ()
    CreatePort :: (CPType a) => Proxy a -> GCMCommand (Port a)
    CreateParameter :: (CPType a) =>  Proxy a -> a -> GCMCommand (Port a)
    Component  :: CP () -> GCMCommand ()

-- A GRACeFUL concept map
type GCM a = Program GCMCommand a

-- Syntactic sugars
output :: (CPType a, Show a) => Port a -> String -> GCM ()
output p = Instr . (Output p)

createPort :: (CPType a) => GCM (Port a)
createPort = Instr (CreatePort Proxy)

createParameter :: (CPType a) => a -> GCM (Port a)
createParameter = Instr . (CreateParameter Proxy)

component :: CP () -> GCM ()
component = Instr . Component

-- Some derived operators
link :: (CPType a, Eq a) => Port a -> Port a -> GCM ()
link p1 p2 = component $ do
                            v1 <- value p1
                            v2 <- value p2
                            assert $ v1 === v2

fun :: (CPType a, CPType b, Eq b) => (CPExp a -> CPExp b) -> GCM (Port a, Port b)
fun f = do
            pin  <- createPort
            pout <- createPort
            component $ do
                            i <- value pin
                            o <- value pout
                            assert $ o === f i
            return (pin, pout)

-- Compilation
data CompilationState = CompilationState {outputs      :: [String],
                                          expressions  :: [String],
                                          declarations :: [String],
                                          nextVarId    :: Int}
type IntermMonad a = State CompilationState a

-- Translation
translateGCMCommand :: GCMCommand a -> IntermMonad a
translateGCMCommand (Output p s) =
    do
        let i = portID p
        state <- get
        put $ state {outputs = (s++"=\\(v"++(show i)++")\\n"):(outputs state)}
translateGCMCommand (CreatePort proxy) =
    do
        state <- get
        let vid = nextVarId state
            dec = "var " ++ (typeDec proxy) ++ ": v"++(show vid)++";"
            state' = state {nextVarId = vid+1, declarations = dec:(declarations state)}
        put state'
        return $ Port vid
translateGCMCommand (CreateParameter proxy def) =
    do
        state <- get
        let vid = nextVarId state
            -- the value
            dec = "var " ++ (typeDec proxy) ++ ": v"++(show vid)++";"
            -- has been acted upon
            dec2 = "var bool: a"++(show vid)++";"
            -- default value
            exp = "not a"++(show vid)++" ==> (v"++(show vid)++" == "++(show def)++")"
            state' = state {nextVarId = vid+1,
                            expressions = exp:(expressions state),
                            declarations = dec:dec2:(declarations state)}
        put state'
        return $ Port vid
translateGCMCommand (Component cp) =
    do
        state <- get
        let (_, exprs) = runWriter $ interpret translateCPCommands cp
            state'     = state {expressions = (expressions state) ++ exprs}
        put state'

-- Final compilation
compileGCM :: GCM a -> String
compileGCM gcm = stateToString $ (flip execState) (CompilationState [] [] [] 0) $ interpret translateGCMCommand gcm 
    where
        stateToString (CompilationState outs exprs declrs _) = unlines [unlines declrs, unlines exprs] ++ "\nsolve satisfy;\noutput [\""++(concat outs)++"\"];"
