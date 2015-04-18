### Manuscripts and Archives Repository

- Values migrated from the AT UserDefinedBoolean2 field in the Accessions module
  will migrate to user_defined.boolean_2 in ArchivesSpace

  - The value of this field should be used to check the “electronic documents” checkbox in a material_types subrecord.
  - After the material_types subrecord is created that the user_defined.boolean_2 should be set to false

- Values migrated from the AT UserDefinedReal1 field in the Accessions module will migrate to user_defined.real_1 in ArchivesSpace
  - The value of this field should be used to create a new extent subrecord.
  - The portion of this event subrecord should be set to “part”.
  - The extent type should be set to “”Megabytes”.
  - After the "Megabytes" extent is created the User_defined.real_1 should be set to null



### Beinecke Rare Book Library Repository

- The following values from AT should come together to populate the same payments subrecord as part of an accession record

  - Values migrated from the AT UserDefinedBoolean1 field in the Accessions module
    will migrate to user_defined.boolean_1 in ArchivesSpace

    - This value of this field should be used to populate the value of in_lot

  - Values migrated from the AT UserDefinedReal1 field in the Accessions module
    will migrate to user_defined.real_1 in ArchivesSpace

    - The value of this field should be use to populate total_price

  - Values migrated from the AT UserDefinedString3 field in the Accessions module
    will migrate to user_defined.string_3 in ArchivesSpace

    - The value of this field should be used to set the matching enum value in  the currency code field.

  - Values migrated from the AT UserDefinedText2 field in the Accessions module
    will migrate to user_defined.text_2 in ArchivesSpace

    - The tokens in user_defined.text_2 will represent fund codes. Multiple fund codes are pipe delimited.
      For each fund code present in user_defined.text_2, create a Payment subrecord.

        - Each payment should then have a fund code assigned by matching the token from user_defined.text_2
          with a code value in the fund_code enum value list.

        - If no match is available, the token from user_defined.text_2 should be copied to the Payment note field.

  - After payments subrecords have been created,
    original values in user defined fields should be set to null or false, as appropriate


- Values migrated from the AT “Agreement Sent” field in the Accessions module
  will migrate to event records in ArchivesSpace with an enumeration value of “agreement_sent”.

  - If an “Agreement Sent” event is associated with an accession record,
    we want user_defined.boolean_1 to be set to True.

  - After user_defined.boolean_1 is set to True, the “Agreement Sent” event should be deleted.


- Values migrated from the AT ConditionNote field in the Accessions module
  will migrate to the ArchivesSpace condition_description field.

  - These values should be moved to the content_description field.

  - If there is already content in the content_description field,
    concatenate the value of content_description and what had been in AT as ConditionNote (in that order),
    separated by a space and a line break.

  - After these values are moved, condition_description should be set to null.


Values migrated from the AT RightsTransferred field in the Accessions module will migrate to event records in ArchivesSpace with an enumeration value of “rights_transferred.”
If a “Rights Transferred” event is associated with an accession record, we want user_defined.boolean_2 to be set to True.
After user_defined.boolean_2 is set to True, the “Rights Transferred” event should be deleted.
Values migrated from the AT UserDefinedInteger1 field in the Accessions module will migrate to user_defined.integer_1 in ArchivesSpace
The value of this field should be used to create a new extent subrecord.
The portion of this event subrecord should be set to “part”.
The extent type should be set to “Manuscript items”.
Once a new extent has been created, user_defined.integer_1 should be set to null.
Values migrated from the AT UserDefinedInteger2 field in the Accessions module will migrate to user_defined.integer_2 in ArchivesSpace
The value of this field should be used to create a new extent subrecord.
The portion of this event subrecord should be set to “part”.
The extent type should be set to “Non-book format items”.
Once a new extent has been created, user_defined.integer_2 should be set to null.
Values migrated from the AT UserDefinedString2 field in the Accessions module will migrate to user_defined.string_2 in ArchivesSpace
The value of this field should be moved to user_defined.text_1
Once the value has been moved, user_defined.string_2 should be set to blank.
Geographic subjects associated with accession records in Archivists’ Toolkit will migrate to geographic subjects in ArchivesSpace
We want for the string value of geographic subjects associated with accession records to be moved to user_defined.string_3.
We want for this subject to be disassociated with the accession record.
We want for any unlinked subject records to be deleted.
The user_defined.enum_2 field in ArchivesSpace will have two possible values: pa | mssu
We want each accession record migrated from the Archivists’ Toolkit to be given the value “mssu” in user_defined.enum_2.
