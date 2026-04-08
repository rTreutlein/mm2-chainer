#!/usr/bin/env bash

mork run demos/priority_scheduler_demo.mm2 --steps 1 outputs/priority_demo.mm2

echo '== pending =='
sed -n '/^(pending /p' outputs/priority_demo.mm2

echo '== selected =='
sed -n '/^(selected /p' outputs/priority_demo.mm2
