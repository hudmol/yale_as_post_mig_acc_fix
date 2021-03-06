# yale_as_post_mig_acc_fix

Post-migration Accession data fixes for Yale ArchivesSpace.

This repoository contains the following files:
- **SPECIFICATION.md** - contains the specification for the data changes. This is based on the original requirements provided by Yale, and has been amended to reflect clarifications and refinements that have occurred since it was originally written.
- **accession_fixes.rb** - a ruby script that applies the data fixes described in the specification.
- **config.rb** - default configuration settings for both of the scripts.
- **delete_unlinked_subjects.rb** - a ruby script for removing all unlinked subject records from an ArchivesSpace instance.


## System Requirements

- A recent version of Ruby
- A running ArchivesSpace instance with data migrated from AT
- Access to the ArchivesSpace backend
- The url of the ArchivesSpace backend
- The username and password of a user on the ArchivesSpace instance that has permission to create/update/delete records


## How to run the fixes

Seriously consider backing up your database before running the scripts.

Here is a quick summary of how to run the scripts:

    $ git clone https://github.com/hudmol/yale_as_post_mig_acc_fix.git
    $ cd yale_as_post_mig_acc_fix
      [edit config.rb to set url, username and password, and optionally other values - alternatively these can be passed on the commandline]
    $ ruby accession_fixes.rb --mssa
      [... lots of output testing fixes on MSSA repo - no changes to the database]
    $ ruby accession_fixes.rb --mssa --commit
      [... lots of output again, this time the addition of the --commit switch turns on updates]
    $ ruby accession_fixes.rb --brbl
      [... as before, this time for BRBL]
    $ ruby accession_fixes.rb --brbl --commit
      [... as before, this time applying the fixes for BRBL]

If you're feeling brave or bored or time challenged you can just dive right in with something like:

    $ ruby accession_fixes.rb -mbqc

When the indexer has caught up with the changes, or indeed at any time, you can delete all unlinked subject records from the ArchivesSpace instance as follows:

    $ ruby delete_unlinked_subjects.rb
      [... again, without the commit switch it will just report - no updates]
    $ ruby delete_unlinked_subjects.rb --commit
      [... actually delete the subjects]


## How it works

The scripts interact with the ArchivesSpace database via the backend API. This allows the scripts to GET JSON representations of the records from the ArchivesSpace backend, manipulate the JSON according to the rules in `SPECIFICATION.md`, and then POST the updated JSON back to the ArchivesSpace backend.

As different rules apply to Accession records from the two repositories, provision is made for running fixes against the repositories separately. When a repository is specified via the appropriate switch the `accession_fixes.rb` script applies the rules for that repository against every Accession record in the repository.

Subjects are global records in ArchivesSpace, so no repository is specified when running `delete_unlinked_subjects.rb`. This script searches against each Subject record in the system for any records that unlink to it. If it fails to find any linking records the Subject record is deleted.

The two scripts take a number of switches that affect their behavior. Many of the switches are the same for both scripts. Default values for the switches can be set in the `config.rb` file. The find out the switches supported by each script, give it a -h or --help switch as follows:

    $ ruby accession_fixes.rb --help
    Usage: accession_fixes.rb [options]
        -a, --backendurl URL             ArchivesSpace backend URL
        -u, --username USERNAME          Username for backend session
        -p, --password PASSWORD          Password for backend session
            --mssacode CODE              Repository code for MSSA
            --brblcode CODE              Repository code for BRBL
        -m, --mssa                       Run MSSA fixes
        -b, --brbl                       Run BRBL fixes
        -c, --commit                     Commit changes to the database
        -q, --quiet                      Only log warnings and errors
        -d, --debug                      Log debugging output
        -h, --help                       Prints this help


    $ ruby delete_unlinked_subjects.rb -h
    Usage: delete_unlinked_subjects.rb [options]
        -a, --backendurl URL             ArchivesSpace backend URL
        -u, --username USERNAME          Username for backend session
        -p, --password PASSWORD          Password for backend session
        -c, --commit                     Commit changes to the database
        -q, --quiet                      Only log warnings and errors
        -d, --debug                      Log debugging output
        -h, --help                       Prints this help


As agreed deleting subjects has been split into a separate script. This is because there is no reliable way of ensuring the indexer has caught up with the changes made by applying the Accession updates before the Subject checks are applied. The Subject script finds out which Subject records to delete by searching against the index for Subjects that don't have any records linking to them - searching is the most efficient way of finding this out. The good news is that the provided `delete_unlinked_subjects.rb` script is a general purpose Subject cleaner-uperer that can be run independently of the `accession_fixes.rb` script at any time to get a report on orphaned Subjects and optionally delete them.
