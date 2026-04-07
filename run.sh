mork run rules.mm2 --steps 100000 --aux-path data.mm2 out.mm2
mork convert metta metta '[2] kb [2] Animal x' 'Yes' out.mm2 kb.mm2
mork convert metta metta '[4] exec 0 $ $' '[4] exec 0 _1 _2' out.mm2 exe.mm2
cat kb.mm2
#cat exe.mm2
