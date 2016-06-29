Synthetic Deltas Imports from SQL Server in FIM
===============================================

 * Matthew Slowe <M.Slowe@kent.ac.uk>
 * June 2016

Problem
-------

 * Large dataset in (or behind) SQL Server
 * 100,000 in master and 250,000 in multi-value
 * This was actually a synthetic dataset based on VIEWs of the Metaverse and was being used to populate AD groups
 * Initial Full Import took 3 days
 * Ongoing Full Imports took hours
 * Need to run this frequently (15 minutes)

Solution
--------

 * Based on a SQL VIEW of the data for FIM to consume…
 * Create a snapshot tables of the VIEW (the “last” run)
 * Create a Delta VIEW between these two datasets
 * Delta imports get slower as delta increases (10sec - 3min)

Base VIEWs
----------
*Examples in SQLite but SQL Server examples in supporting files*

```sql
CREATE TABLE people 	(employee_id, firstname, surname);
CREATE TABLE roles 	(employee_id, role);
CREATE VIEW people_mv  AS  
	SELECT employee_id, 
           'role' AS attribute,
           role   AS string_value
    FROM   roles;
```

### Example data
*See attached fim_delta.sql*
```
sqlite> select * from people;
employee_id  firstname   surname
-----------  ----------  ----------
1            Edmund      Blackadder
2            Sodoff      Baldrick
4            Queen       Elizabeth
3            Bernard     Nursie
 
sqlite> select * from people_mv;
employee_id  attribute   string_value
-----------  ----------  ------------
1            role        lord
1            role        executioner
4            role        queen
3            role        nurse
2            role        dogsbody
```

Create snapshot tables
----------------------
```sql
/* SQL Server */
SELECT * INTO people_copy FROM people;
SELECT * INTO people_mv_copy FROM people_mv;

/* sqlite */
CREATE TABLE people_copy AS 	SELECT * FROM people;
CREATE TABLE people_mv_copy AS 	SELECT * FROM people_mv;
```

Delta VIEW
----------

 * Schema
   * Base table’s data as it is now
   * Changetype column (Add, Delete, Modify)
   * Changes to MV table count as Modifies
 * Combines four SELECTs to cover
   * Add
   * Delete
   * Modify (left and right diff of base table)
 * Add two extra SELECTs to cover changes in multivalue table (more Modifies)

This solution makes extensive use of SQL JOINs of varying types. For more details see http://www.codeproject.com/Articles/33052/Visual-Representation-of-SQL-Joins 

### SQL

```sql
CREATE VIEW people_delta
AS

  /* Adds don't exist in the copy table */
  SELECT p.employee_id,
         p.firstname,
         p.surname,
         'Add' AS changetype
  FROM   people p
         LEFT OUTER JOIN people_copy pc
                      ON p.employee_id = pc.employee_id
  WHERE  pc.employee_id IS NULL

  UNION

  /* Deletes don't exist in the current table */
  SELECT pc.employee_id,
         pc.firstname,
         pc.surname,
         'Delete' AS changetype
  FROM   people_copy pc
         LEFT OUTER JOIN people p
                      ON p.employee_id = pc.employee_id
  WHERE  p.employee_id IS NULL

  UNION

  /* Modify has different values */
  SELECT p.employee_id,
         p.firstname,
         p.surname,
         'Modify' AS changetype
  FROM   people p
         JOIN people_copy pc
           ON p.employee_id = pc.employee_id
  WHERE  p.firstname <> pc.firstname
          OR p.surname <> pc.surname

  UNION

  /* Or any differences in the _mv table should be a modify on the base table */
  SELECT p.employee_id,
         p.firstname,
         p.surname,
         'Modify' AS changetype
  FROM   people p
         JOIN people_mv p_mv
           ON p.employee_id = p_mv.employee_id
         LEFT OUTER JOIN people_mv_copy pc_mv
                      ON p_mv.employee_id = pc_mv.employee_id
                         AND p_mv.attribute = pc_mv.attribute
                         AND p_mv.string_value = pc_mv.string_value
  WHERE  pc_mv.employee_id IS NULL

  UNION

  SELECT pc.employee_id,
         pc.firstname,
         pc.surname,
         'Modify' AS changetype
  FROM   people pc
         JOIN people_mv_copy pc_mv
           ON pc.employee_id = pc_mv.employee_id
         LEFT OUTER JOIN people_mv p_mv
                      ON p_mv.employee_id = pc_mv.employee_id
                         AND p_mv.attribute = pc_mv.attribute
                         AND p_mv.string_value = pc_mv.string_value
  WHERE  p_mv.employee_id IS NULL;
```

Example changes
---------------

```
sqlite> select * from people;
employee_id  firstname   surname
-----------  ----------  ----------
1            Edmund      Blackadder
2            Sodoff      Baldrick
4            Queen       Elizabeth <- removed
3            Bernard     Nursie    <- removed
5            Kevin       Darling   <- added
6            Anthony Ce  Melchett  <- added
 
sqlite> select * from people_mv;
employee_id  attribute   string_value
-----------  ----------  ------------
1            role        captain      <-- changed
1            role        executioner  <-- removed
2            role        dogsbody
2            role        private      <-- added
4            role        queen        <-- removed
3            role        nurse        <-- removed
5            role        captain      <-- added
6            role        general      <-- added
```

```sql
BEGIN TRANSACTION;
SELECT * FROM people_delta;

DELETE FROM people WHERE employee_id IN (3,4);
DELETE FROM roles WHERE employee_id IN (1,3,4);

INSERT INTO people VALUES(5,'Kevin','Darling');
INSERT INTO people VALUES(6,'Anthony Cecil Hogmanay','Melchett');

INSERT INTO roles VALUES(1,'captain');
INSERT INTO roles VALUES(2,'private');
INSERT INTO roles VALUES(5,'captain');
INSERT INTO roles VALUES(6,'general');

SELECT * FROM people_delta;
ROLLBACK;
```

```
employee_id  firstname   surname     changetype
-----------  ----------  ----------  ----------
1            Edmund      Blackadder  Modify
2            Sodoff      Baldrick    Modify
3            Bernard     Nursie      Delete
4            Queen       Elizabeth   Delete
5            Kevin       Darling     Add
5            Kevin       Darling     Modify
6            Anthony Ce  Melchett    Add
6            Anthony Ce  Melchett    Modify
```

Rebasing the snapshot tables
----------------------------

 * Unable to do atomically as part of a Run Profile 
 * Pick a safe time! When no other SYNC jobs are running
 * If not large numbers of changes in a day, overnight?
 * Done as SQL Agent job

```sql
DELETE FROM people_copy;
DELETE FROM people_mv_copy;
INSERT INTO people_copy SELECT * FROM people;
INSERT INTO people_mv_copy SELECT * FROM people_mv;
```

Group Populator in Practice
---------------------------

 * Base VIEW has all groups UNIONed with all users
   * Groups: name,  “group” (projected/joined on name)
   * Users: objectid, “user” (joined on objectid)
 * Multivalue VIEW has all memberships in
   * samAccountName (of group)
   * "member"
   * samAccountName (of user, marked as reference)
 * Copy tables of these two views
 * Delta VIEW then diffs them all… boom!


Possible applications
---------------------

 * Native Group Populator (using VIEWs of the Metaverse?)
 * Links to slow databases or ones you don’t control (eg Linked Server to MySQL), couple with a table copy for Full Import

Known issues
------------
 * Delta Import gets slower through day
 * Need to be careful when scheduling so as to not miss updates
 * Double entry on Add (errant Modifies)

More info
---------

 * The original blog post on which this presentation was based is at http://blogs.kent.ac.uk/unseenit/group-populator-for-fim/
 * SQLFiddle at http://sqlfiddle.com/#!5/f68ac/1/0
