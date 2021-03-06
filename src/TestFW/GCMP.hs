module TestFW.GCMP where

import GL
import TestFW.GenT
import qualified Test.QuickCheck as QC
import Control.Monad.Trans
import Control.Monad.Trans.State as S

type GCMP a = S.StateT Int (GenT GCM) a

forall :: QC.Gen a -> GCMP a
forall = lift . liftGen

liftGCM :: GCM a -> GCMP a
liftGCM = lift . lift

property :: CPExp Bool -> GCMP ()
property expr =
    do
     s <- get
     put (s + 1)
     liftGCM $
        do
            p <- createPort
            component $
                do
                    v <- value p
                    assert $ v === expr
            output p $ "prop_" ++ (show s)

makeGenerator :: GCMP a -> QC.Gen (GCM a)
makeGenerator gcmp = runGenT $ S.evalStateT gcmp 0

-- --------------------------------------------------------------
