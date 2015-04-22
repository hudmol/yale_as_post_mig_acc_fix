# yale_as_post_mig_acc_fix

Post-migration Accession data fixes for Yale ArchivesSpace.

This repoository containns the following files:
- **SPECIFICATION.md** - contains the specification for the data changes. This is based on the original requirements provided by Yale, and has been amended to reflect clarifications and refinements that have occurred since it was originally written.
- **accession_fixes.rb** - a ruby script that applies the data fixes described in the specification.
- **config.rb** - default configuration settings for both of the scripts.
- **delete_unlinked_subjects.rb** - a ruby script for removing all unlinked subject records from an ArchivesSpace instance.

See below for a full description of each of these files.

## System Requirements

- A recent version of Ruby
- A running ArchivesSpace instance with data migrated from AT
- Access to the ArchivesSpace backend
- The url of the ArchivesSpace backend
- The username and password of a user on the ArchivesSpace instance that has permission to create/update/delete records

## How to run the fixes

Seriously consider backing up your database before running the scripts.

Here is a quick summary of how to run the scripts:

    git clone https://github.com/hudmol/yale_as_post_mig_acc_fix.git
    cd yale_as_post_mig_acc_fix
    [edit config.rb to set url, username and password, and optionally other values - alternatively these can be passed on the commandline]
    ruby accession_fixes.rb --mssa
    [... lots of output testing fixes on MSSA repo - no changes to the database]
    ruby accession_fixes.rb --mssa --commit
    [... lots of output again, this time the addition of the --commit switch turns on updates]
    ruby accession_fixes.rb --brbl
    [... as before, this time for BRBL]
    ruby accession_fixes.rb --brbl --commit
    [... as before, this time applying the fixes for BRBL]

If you're feeling brave or bored or time challenged you can just dive right in with something like:

    ruby accession_fixes.rb -mbqc

When the indexer has caught up with the changes, or indeed at any time, you can delete all unlinked subject records from the ArchivesSpace instance as follows:

    ruby delete_unlinked_subjects.rb
    [... again, without the commit switch it will just report - no updates]
    ruby delete_unlinked_subjects.rb --commit
    [... actually delete the subjects]
