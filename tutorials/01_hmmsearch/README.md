# Example 01 — Searching an HMM database across many genomes

## Preparing the data

```bash
cd "~/modi_mount/ucph-modi/tutorials/01_hmmsearch"
```

Our initial retrieval and setup of data will not require a lot of computing power, so we can stick to using the *login* node for now.

First we will create a `conda` environment with the tools we're going to use. `conda` is already installed and available on the *login* node:

```bash
conda create -y --prefix "~/modi_mount/conda_envs/ucph-modi-01-hmmer" -c conda-forge -c bioconda parallel aria2 hmmer
```

This will create an environment called `ucph-modi-01-hmmer`, and search the channels `conda-forge` and `bioconda` for `parallel`, `aria2`, and `hmmer`, installing them. By specifying the prefix as `~/modi_mount/conda_envs/`, we are ensuring that the environment is established in `modi_mount`, so it will be accessible to all *compute* nodes later on.

Activate the environment:

```bash
conda activate "~/modi_mount/conda_envs/ucph-modi-01-hmmer"
```

`parallel` is a great tool for splitting commands across multiple CPUs, it's useful on a regular computer with a handful of CPUs, but especially powerful when you can split jobs across tens or hundreds of CPUs on a cluster.

By default, every time you run `parallel`, it prints citation information, to avoid this run the following command once, and agree:

```bash
parallel --citation
```

Next we'll use `parallel` to download the first 20 Pfam seed alignments to build HMMs from (we could also just download the HMMs themselves, but this way you get to experience using `parallel` some more).

First make a directory for the alignments:

```bash
mkdir -p sto
```

```bash
parallel -j 5 'curl --progress-bar -L -o sto/PF000{}_seed.sto.gz "https://www.ebi.ac.uk/interpro/wwwapi//entry/pfam/PF000{}/?annotation=alignment:seed&download"' ::: {01..20}
```

With this command, `parallel` will take the output of `{01..20}` (which is a sequence of numbers `00` to `20`), and pass it to the command `curl --progress-bar -L -o sto/PF000{}_seed.sto.gz "https://www.ebi.ac.uk/interpro/wwwapi//entry/pfam/PF000{}/?annotation=alignment:seed&download"`, inserting each number where there is a `{}`.

The `-j 5` flag tells parallel to split this process over `5` CPUs, so five alignments will be downloaded at a time.

Now uncompress these files (in parallel again):

```bash
parallel -j 5 'gunzip sto/PF000{}_seed.sto.gz' ::: {01..20}
```

Next we'll run `hmmbuilld` to make the HMMs, again, this process is not very resource intensive, so we'll just do it on the login node:

```bash
mkdir -p hmm
```

```bash
parallel -j 5 'hmmbuild hmm/PF000{}.hmm sto/PF000{}_seed.sto' ::: {01..20}
```

Concatenate these HMMs into a single database:

```bash
cat hmm/*.hmm > PFAM.hmm
```

Now we'll download some proteomes to search against. Here we're going to use `aria2c`, a great tool for downloading in parallel from a list of urls:

```bash
mkdir -p faa
```

```bash
aria2c -i uniprotKB_2024_06_n128.txt -d faa -j 8
```

`uniprotKB_2024_06_n128.txt` contains the URLs for the protein FASTA files of the first 128 genomes in the UniprotKB Reference Database, as of the June 2024 (current) release. Here, we're telling `aria2c` to download these files across 8 CPUs and put them in `faa/`.

Uncompress the files:

```bash
parallel --progress -j 8 'gunzip -k {}' ::: $(find faa -name "*.fasta.gz")
```

## Submitting to the cluster

Set up a directory for the output:

```bash
mkdir -p domtblout
```

Included in this section of the repo are two basic scripts:

##### `01_run_hmmsearch.sh`

```
01 | #!/usr/bin/env bash
02 |
03 | export DIR="~/modi_mount/ucph-modi/tutorials/01_hmmsearch"
04 |
05 | source "${CONDA_DIR}/etc/profile.d/conda.sh"
06 |
07 | conda activate ~/modi_mount/conda_envs/conda_test
08 |
09 | function hmmsearch_wrapper() {
10 |     local id=$(basename "${1%.fasta}")
11 |     hmmsearch --acc --domtblout "${DIR}/domtblout/${id}.domtblout" "${DIR}/PFAM.hmm" "${1}"
12 | }
13 |
14 | export -f hmmsearch_wrapper
15 |
16 | parallel --progress -j 32 'hmmsearch_wrapper {}' ::: $(find ${DIR}/faa -name "*.fasta")
```

This is a regular `bash` script that one might run on their own laptop.

`LINE 01:` Here we specify that this code should be evaluated by `bash`.

`LINE 03:` First we are declaring a variable `${DIR}`, which contains the path to our working directory. Here we are using `export` to make sure that the variable is available to all *subprocesses* started by subsequent functions. This becomes relevant when using variables with `parallel`, because it is actually spinning up a *subprocess* for each job it creates.

`LINE 04:` Next we are *sourcing* the script `"${CONDA_DIR}/etc/profile.d/conda.sh"` to activate `conda`.

`LINE 07:` Here we activate the environment we established earlier.

`LINE 09:` When executing more complex (e.g. multi-line) commands with parallel, sometimes it helps to declare a new function that wraps all of those commands together, making the code more readable and easier to debug. Here we declare a new function `hmmsearch_wrapper`

`LINE 10:` In the first step of the function, we are doing some tricks with parameter expansion to remove `".fasta"` from the end of whatever `${1}` is (the value of `${1}` is going to be the first argument passed to the function `hmmsearch_wrapper`, in this case we're going to be passing it the paths to our FASTA files), so it converts `~/modi_mount/tutorials/01_hmmsearch/faa/UP000000212_1234679.fasta` into `~/modi_mount/tutorials/01_hmmsearch/faa/UP000000212_1234679` for example. Then we're passing that to `basename`, which trims a path down to its 'base', e.g. `UP000000212_1234679`. We're then declaring a variable `${id}` which holds this value. The variable is `local`, so it's only accessible inside this function, this is generally good practice.

`LINE 11:` This step of the function runs `hmmsearch`, writing the result in domain table format in a filename constructed from the ID we generated above.

`LINE 14:` Similarly to variables, we have to explicitly `export` this function so it is accessible to *subprocesses* generated by `parallel`.

`LINE 16:` Finally, we are actually running `parallel`, passing it a list of the FASTA files found in our `faa/` directory, and then passing these file names to our `hmmsearch_wrapper`. The computation is split across 32 CPUs, so we're effectively dividing the time it would take to run `hmmsearch` sequentialy on 128 genomes by 32, i.e. down to four. Very quick!

##### `01_run_hmmsearch.slurm`

```
01 | #!/usr/bin/env bash
02 | 
03 | #SBATCH --partition=modi_devel
04 | #SBATCH --job-name=tutorial_01
05 | #SBATCH --time=00:15:00
06 | #SBATCH --cpus-per-task=32
07 | #SBATCH --output=logs/%x_%A_%N_stdout.log
08 | #SBATCH --error=logs/%x_%A_%N_stderr.log
09 | 
10 | srun singularity exec ~/modi_images/hpc-notebook-23.11.9.sif \
11 |   ~/modi_mount/ucph-modi/tutorials/01_hmmsearch/01_run_hmmsearch.sh
```

To actually send our job to the *compute* nodes, we need to wrap it in a SLURM script. This is essentially the same as a `bash` script, but with some additional toppings. You could technically combine these two scripts, but this is a cleaner way of approaching things.

`LINE 01:` Here's the usual `bash` shebang.

`LINE 03:` Here's the start of the additional toppings. These are SLURM *directives*. None of them are strictly essential (they will fall back to defaults), and not all options are covered here. If you want to know all the options, read the [SLURM documentation](https://slurm.schedmd.com/sbatch.html).

- `--partition` specifies what partition we want to use ([as discussed in Basic Concepts](../00_basic_concepts/)).

- `--job-name` specifies a name for the job, which appears in `squeue`, and will be used to name the outputs.

- `--time` specifies how long we want to reserves the resources. If you omit this, the job will simply run until completed, or an error occurs, or the maximum time for the partition is reached. `00:15:00` is the maximum time for this partition. We know the job should complete before this, so we could specify a shorter time incase there's a bug we missed that stalls execution. This would stop the job quicker, freeing up resources for others to use.

- `--cpus-per-task` specifies how many CPUs we want to reserve. Here, we're reserving 32, one for each `parallel` job.

- `--output` specifies where the standard output (e.g. what would usually be returned by the terminal) should be written. We're going to write to a directory called `logs/`, and construct the file name from the job name (`%x`), the job ID (`%A`) and the node name (`%N`).

- `--error` specifies where the standard error (e.g. what would usually be returned by the terminal) should be written. We're doing the same here as with the output.

`LINE 10:` The way that MODI is set up, we need to spin up any *compute* jobs inside a singularity container that replicates the software we have available on the *login* node (i.e. this makes `conda` available, so we can actually load up our environment). If this were not an issue (as is the case for other clusters you may encounter), we could omit this line, and simply copy-paste the code from the previous script into this one. This line is essentially telling SLURM (via `srun`) to run `singularity` (a containerization software) in `exec` mode, using the container image called `~/modi_images/hpc-notebook-23.11.9.sif`, and in that container execute our previous script.
