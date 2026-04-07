mork run rules.mm2 --steps 40 --aux-path simple_data.mm2 simple_out.mm2

echo '== animal answers =='
sed -n '/^(kb (Animal /p' simple_out.mm2

#echo '== pending =='
#sed -n '/^(pending /p' simple_out.mm2

echo '== selected =='
sed -n '/^(selected /p' simple_out.mm2

echo '== kb =='
sed -n '/^(kb /p' simple_out.mm2

#echo '== unresolved proof templates =='
#sed -n '/^(exec-template (exec 0 /p' simple_out.mm2
