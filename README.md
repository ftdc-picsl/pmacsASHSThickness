# pmacsASHSThickness

ASHS thickness pipeline, for computing thickness on ASHS segmentation results. The script
is a wrapper for the PMACS LPC, which calls the containerized thickness pipeline by Long
Xie.

The script will run on output from the
[pmacsASHS](https://github.com/ftdc-picsl/pmacsASHS) script, or from calling ASHS
`ashs_main.sh` directly. Because it searches the input directory for matching files, the
input directory must only contain files from one session.

## Hard-coded dependences

### ASHS thickness container

FTDC users can use the installed image. Others will need to build a Singularity image from
the [Docker source](https://hub.docker.com/r/longxie/ashsthk), and edit the path in the
run script.

### ASHS thickness multi-atlas template

The 3T T1w template is installed for FTDC users, others will need to obtain the template.
The template path can be set at run time with `-a`.


## Running the script

By default, both hemispheres are processed, but this can be changes with the `-e` option.
BSC users may want to run both hemispheres separately to avoid run time limitations.

### Pipeline stages

The container supports staged execution, by default stages 1 through 5 are run, which
produces thickness using a "variant template". Stages 6-8 use a "unified template".


## Computational requirements

Using the default stages, run time is approximately 7 hours per hemisphere on the FTDC
compute nodes. Long Xie recommends 8Gb of RAM.

Multi-threading is handled automatically based on the number of processors reserved for
the LSB job. Greedy will use multiple threads but the geodesic shooting runs single
threaded - this may be changed in later versions. Therefore, it may be most efficient to
run with a single core.

## Output

For each hemisphere, there are three outputs when running the default stages:

```
[hemisphere]_template_[group]_fitted_mesh.vtk
[hemisphere]_template_[group]_momenta.vtk
[hemisphere]_thickness.csv
```

The group is an integer group identifier, determined automatically by the pipeline.


## Citation

If using this software for research, please cite

Long Xie, et al, "Multi-template analysis of human perirhinal cortex in brain MRI:
Explicitly accounting for anatomical variability", *NeuroImage* 2017 Jan 1; 144(Pt A):183-202,
PMID: [27702610](https://pubmed.ncbi.nlm.nih.gov/27702610/), PMCID:
[PMC5183532](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5183532/), DOI:
10.1016/j.neuroimage.2016.09.070.