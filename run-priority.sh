mork run simple_priority.mm2 --steps 1 simple_priority_out.mm2

echo '== pending =='
sed -n '/^(pending /p' simple_priority_out.mm2

echo '== selected =='
sed -n '/^(selected /p' simple_priority_out.mm2
