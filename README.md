# pmacsASHSThickness

ASHS thickness pipeline, for computing thickness on ASHS segmentation results. The script
is a wrapper for the PMACS LPC, which calls the containerized thickness pipeline by Long
Xie.

The [ASHS thickness paper](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5183532/) has a
lot more detail on the process and the outputs.


# Input

The input to the wrapper is a directory containing MTL segmentations from ASHS. Currently,
only ASHS T1w output is supported. The script will search the input directory for output
files in the `fastashs` format, as implemented in
[pmacsASHS](https://github.com/ftdc-picsl/pmacsASHS), or in the original format from
calling ASHS `ashs_main.sh` directly. Because the script searches the input directory for
matching files, the input directory must only contain files from one session.

The `pmacsASHS` format is the same as the ASHS `fastashs` wrapper, where segmentations
have the suffix `_MTLSeg_[left|right].nii.gz`. Standard ASHS segmentations have the
suffix `_[left|right]}_lfseg_heur.nii.gz`.

The script does not detect what atlas was used in the ASHS segmentation - users must
ensure that input was segmented with the ASHS-T1 pipeline.


## Dependencies

Dependencies have been installed for FTDC LPC users.


### ASHS thickness container

Build a Singularity image from the [Docker
source](https://hub.docker.com/r/longxie/ashsthk), and edit the path in the run script.
The wrapper has been tested with `v4`, built with

```
singularity build ashsthk-4.0.sif docker://longxie/ashsthk:v4
```

### ASHS thickness multi-atlas template

The template path can be set at run time with `-a`. The default template is for ASHS-T1
segmentations only. A template for ASHS-T2 segmentations is under development.


## Running the script

By default, both hemispheres are processed, but this can be changes with the `-e` option.
BSC users may want to run both hemispheres separately to avoid run time limitations.

### Pipeline stages

The container supports staged execution, by default stages 1 through 5 are run, which
produces thickness using a "variant template", selected to best fit the individual
anatomy. Stages 6-8 use a "unified template", which fits a common coordinate coordinate
system to the segmentation mesh, enabling pointwise thickness comparisons.

### Computational requirements

Using the default stages, run time is approximately 7 hours per hemisphere on the FTDC
compute nodes. Long Xie recommends 8Gb of RAM.

Multi-threading is handled automatically based on the number of processors reserved for
the LSB job. Greedy will use multiple threads but the geodesic shooting runs single
threaded - this may be changed in later versions. Therefore, it may be most efficient to
run with a single core.


## Output

For each hemisphere, there are three outputs when running the default stages:

* `[hemisphere]_template_[group]_fitted_mesh.vtk` - segmentation mesh with pointwise
  thickness data.

* `[hemisphere]_template_[group]_momenta.vtk` - geodesic shooting momenta.

* `[hemisphere]_thickness.csv` - Regional average thickness and fit quality measures.

The group is an integer group identifier, which identifies the selected variant template.


## Citation

If using this software for research, please cite

Long Xie, et al, "Multi-template analysis of human perirhinal cortex in brain MRI:
Explicitly accounting for anatomical variability", *NeuroImage* 2017 Jan 1; 144(Pt A):183-202,
PMID: [27702610](https://pubmed.ncbi.nlm.nih.gov/27702610/), PMCID:
[PMC5183532](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5183532/), DOI:
10.1016/j.neuroimage.2016.09.070.