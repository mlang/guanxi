{-# language DeriveTraversable #-}

module Unaligned
  ( View(..)
  , Cons(..)
  , Uncons(..)
  , Snoc(..)
  , Unsnoc(..)
  , Nil(..)
  , Q(..)
  , Cat(..)
  , Rev(..)
  ) where

import Prelude hiding (id,(.))
import Control.Category
import Data.Bifunctor
import Data.Bifoldable
import Data.Bitraversable

--------------------------------------------------------------------------------
-- * Interface
--------------------------------------------------------------------------------

data View a b = Empty | a :&: b
  deriving (Show, Functor, Foldable, Traversable)

instance Bifunctor View where
  bimap _ _ Empty = Empty
  bimap f g (a :&: b) = f a :&: g b

instance Bifoldable View where
  bifoldMap _ _ Empty = mempty
  bifoldMap f g (a :&: b) = f a <> g b

instance Bitraversable View where
  bitraverse _ _ Empty = pure Empty
  bitraverse f g (a :&: b) = (:&:) <$> f a <*> g b

class Cons t where
  cons :: a -> t a -> t a

class Nil t where
  nil :: t a

class Uncons t where
  uncons :: t a -> View a (t a)

class Unsnoc t where
  unsnoc :: t a -> View (t a) a

class Snoc t where
  snoc :: t a -> a -> t a

class Singleton t where
  singleton :: a -> t a

--------------------------------------------------------------------------------
-- Reversing containers
--------------------------------------------------------------------------------

newtype Rev f a = Rev { runRev :: f a }
  deriving (Show, Functor, Foldable, Traversable)

instance Semigroup (f a) => Semigroup (Rev f a) where
  Rev a <> Rev b = Rev (b <> a)

instance Monoid (f a) => Monoid (Rev f a) where
  mempty = Rev mempty

instance Nil t => Nil (Rev t) where
  nil = Rev nil

instance Cons t => Snoc (Rev t) where
  snoc (Rev t) f = Rev (cons f t)

instance Uncons t => Unsnoc (Rev t) where
  unsnoc (Rev t) = case uncons t of
    l :&: r -> Rev r :&: l
    Empty -> Empty

instance Unsnoc t => Uncons (Rev t) where
  uncons (Rev t) = case unsnoc t of
    l :&: r -> r :&: Rev l
    Empty -> Empty

instance Snoc t => Cons (Rev t) where
  cons a (Rev b) = Rev (snoc b a)

instance Singleton t => Singleton (Rev t) where
  singleton = Rev . singleton

--------------------------------------------------------------------------------
-- * Thrists
--------------------------------------------------------------------------------

instance Nil [] where
  nil = []

instance Cons [] where
  cons = (:)

instance Uncons [] where
  uncons [] = Empty
  uncons (a:b) = a :&: b

instance Singleton [] where
  singleton a = [a]

--------------------------------------------------------------------------------
-- * Queues
--------------------------------------------------------------------------------

data Q a = Q [a] (Rev [] a) [a]
  deriving Show

instance Nil Q where
  nil = Q nil nil nil

instance Cons Q where
  cons a (Q f r s) = Q (a:f) r (a:s)

instance Uncons Q where
  uncons (Q [] (Rev []) _) = Empty
  uncons (Q (x:f) r s) = x :&: exec f r s
  uncons _ = error "Q.uncons: invariants violated"

instance Singleton Q where
  singleton a = Q [a] nil nil

instance Snoc Q where
  snoc (Q f r s) a = exec f (snoc r a) s

exec :: [a] -> Rev [] a -> [a] -> Q a
exec xs ys (_:t) = Q xs ys t
exec xs ys []    = Q xs' (Rev []) xs' where xs' = rotate xs ys nil

rotate :: [a] -> Rev [] a -> [a] -> [a]
rotate [] (Rev [y]) a = y:a
rotate (x:xs) (Rev (y:ys)) a = x:rotate xs (Rev ys) (y:a)
rotate _ _ _ = error "Q.rotate: invariant broken"

--------------------------------------------------------------------------------
-- * Catenable lists
--------------------------------------------------------------------------------

data Cat a = E | C a (Q (Cat a))
  deriving Show

instance Semigroup (Cat a) where

  E <> xs = xs
  xs <> E = xs
  C x xs <> ys = link x xs ys

instance Monoid (Cat a) where
  mempty = E

link :: a -> Q (Cat a) -> Cat a -> Cat a
link x xs ys = C x (snoc xs ys)

-- O(1+e) where e is the number of empty catenable lists in the Q
linkAll :: Q (Cat a) -> Cat a
linkAll q = case uncons q of
  c@(C a t) :&: q' -> case uncons q' of
    Empty -> c
    _ -> link a t (linkAll q')
  E :&: q' -> linkAll q' -- recursive case in case of empty queues, unused
  Empty -> E 

instance Nil Cat where
  nil = E

instance Uncons Cat where
  uncons E = Empty
  uncons (C a q) = a :&: linkAll q

instance Cons Cat where
  cons a E  = C a nil
  cons a ys = link a nil ys

instance Singleton Cat where
  singleton a = C a nil

instance Snoc Cat where
  snoc xs a = xs <> singleton a
