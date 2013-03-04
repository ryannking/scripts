#! /bin/sh
#######################################################################
### Set case parameters
### user: User
### jobn: The name of the output file in data directory
### pnum: Project number for charging/allocation purposes
### rund: Name of the run directory where data are placed
### dirm: Location of the submit script and output directory
### csrc: Directory containing code source
### nodes: Number of nodes
### cores: Number of MPI processes to start on each node; 12 cores/node on Janus

user=ryki5239
jobn=precursorABLNeutral
pnum=UCB00000168
rund=run1
dirm=/lustre/janus_scratch/ryki5239/SOWFA/precursorABL/neutral
csrc=/home/ryki5239/OpenFOAM/OpenFOAM-2.1.1/tutorialsSOWFA/precursorABL/neutral
nodes=12
cores=12

#######################################################################

#######################################################################
### Setup run
echo 'Setting up run'
cd $dirm
mkdir $rund
rm -f -r $rund/*
cp -r $csrc/* $rund

. /curc/tools/utils/dkinit
reuse Moab
reuse Torque
reuse .gcc-4.3.4
reuse OpenFOAM-2.1.1

#######################################################################

#######################################################################
### Execute code, either locally or using PBS
echo 'Execute step'
#PBS -N $jobn
#PBS -l walltime=24:00:00
#PBS -l nodes=$nodes:ppn=$cores:
#PBS -A $pnum
#PBS -q janus-small
#PBS -o out.out
#PBS -e err.err

sed -i "s/numberOfSubdomains [0-9]*;/numberOfSubdomains\ $(($nodes*$cores));/" system/decomposeParDict

# Function for refining the mesh globally in parallel.
refineMeshByCellSet()
{
   for i in `seq 1 $1`;
   do
      echo "LEVEL $i REFINEMENT"
      echo "   selecting cells to refine..."
      mpirun -np $(($nodes*$cores)) topoSet -parallel > log.toposet.$i 2>&1

      echo "   refining cells..."
      mpirun -np $(($nodes*$cores)) refineHexMesh -parallel -overwrite domain > log.refineHexMesh.$i 2>&1
      shift
   done
}

# starting with the proper control dict
cp system/controlDict.1 system/controlDict

# Make the mesh using blockMesh (serial)
echo "BUILDING THE MESH WITH blockMesh..."
blockMesh > log.blockMesh 2>&1

# Get rid of any initial files and replace with 0.original files (serial)
rm -rf 0
cp -rf 0.original 0

# Decompose the mesh and solution files (serial)

echo "DECOMPOSING THE DOMAIN WITH decomposePar..."
decomposePar -cellDist -force > log.decomposePar 2>&1

# Refine the mesh and solution files (enter number of refinement levels) (parallel)
refineMeshByCellSet 1

# Initialize the solution files (parallel)
echo "INITIALIZING THE FLOW FIELD..."
mpirun -np $(($nodes*$cores)) setFieldsABL -parallel > log.setFieldsABL 2>&1

# Run the solver up to 12000 s (parallel)
echo "RUNNING THE SOLVER, PART 1..."
cp system/controlDict.1 system/controlDict
mpirun -np $(($nodes*$cores)) ABLPisoSolver -parallel > log.ABLPisoSolver.1 2>&1

# Run the solver starting at 12000 s up to 14000s, saving planes of inflow
# data on the south and west boundaries every time step to be used as
# boundary conditions for the wind plant case. (parallel)
echo "RUNNING THE SOLVER, PART 2..."
cp system/controlDict.2 system/controlDict
mpirun -np $(($nodes*$cores)) ABLPisoSolver -parallel > log.ABLPisoSolver.2 2>&1
