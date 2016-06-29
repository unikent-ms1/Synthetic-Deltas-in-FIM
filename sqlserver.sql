CREATE TABLE people (employee_id int, firstname varchar(32), surname varchar(32));
INSERT INTO "people" VALUES(1,'Edmund','Blackadder');
INSERT INTO "people" VALUES(2,'Sodoff','Baldrick');
INSERT INTO "people" VALUES(4,'Queen','Elizabeth');
INSERT INTO "people" VALUES(3,'Bernard','Nursie');
CREATE TABLE roles (employee_id int, role varchar(32));
INSERT INTO "roles" VALUES(1,'knight');
INSERT INTO "roles" VALUES(4,'queen');
INSERT INTO "roles" VALUES(3,'nurse');
INSERT INTO "roles" VALUES(2,'dogsbody');
CREATE TABLE people_copy (employee_id int, firstname varchar(32), surname varchar(32));
INSERT INTO "people_copy" VALUES(1,'Edmund','Blackadder');
INSERT INTO "people_copy" VALUES(2,'Sodoff','Baldrick');
INSERT INTO "people_copy" VALUES(4,'Queen','Elizabeth');
INSERT INTO "people_copy" VALUES(3,'Bernard','Nursie');
CREATE TABLE people_mv_copy (employee_id int, attribute varchar(32), string_value varchar(32));
INSERT INTO "people_mv_copy" VALUES(1,'role','knight');
INSERT INTO "people_mv_copy" VALUES(4,'role','queen');
INSERT INTO "people_mv_copy" VALUES(3,'role','nurse');
INSERT INTO "people_mv_copy" VALUES(2,'role','dogsbody');
GO

CREATE VIEW people_mv as select employee_id, 'role' as attribute, role as string_value from roles;
GO

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
GO


/********************/

SELECT * FROM people_delta;

BEGIN TRANSACTION;
UPDATE roles SET role='captain' WHERE employee_id=1;
DELETE FROM people WHERE employee_id IN (3,4);
DELETE FROM roles WHERE employee_id IN (3,4);
INSERT INTO people VALUES(5,'Kevin','Darling');
INSERT INTO people VALUES(6,'Anthony Cecil Hogmanay','Melchett');
INSERT INTO roles VALUES(5,'captain');
INSERT INTO roles VALUES(6,'general');
INSERT INTO roles VALUES(2,'private');
SELECT * FROM people_delta;
ROLLBACK;
