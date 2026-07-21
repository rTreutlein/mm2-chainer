:- module(mm2_batch, [mork_add_atoms/2]).

:- use_module(library(thread)).

metta_cons_list([], []).
metta_cons_list([cons, Head, Tail], [Head|Rest]) :-
    !,
    metta_cons_list(Tail, Rest).
metta_cons_list(List, List) :-
    is_list(List).

serialize_mork_atoms(Atoms, Texts) :-
    length(Atoms, Count),
    ( Count >= 8
    -> concurrent_maplist(swrite, Atoms, Texts)
    ;  maplist(swrite, Atoms, Texts)
    ).

mork_add_atoms(MettaAtoms, true) :-
    metta_cons_list(MettaAtoms, Atoms),
    serialize_mork_atoms(Atoms, Texts),
    atomics_to_string(Texts, " ", Source),
    mork("add-atoms", Source, Result),
    sub_string(Result, 0, 2, _, "OK").
