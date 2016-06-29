DELETE FROM people WHERE employee_id IN (3,4);
DELETE FROM roles WHERE employee_id IN (1,3,4);
INSERT INTO people VALUES(5,'Kevin','Darling');
INSERT INTO people VALUES(6,'Anthony Cecil Hogmanay','Melchett');
INSERT INTO roles VALUES(1,'captain');
INSERT INTO roles VALUES(2,'private');
INSERT INTO roles VALUES(5,'captain');
INSERT INTO roles VALUES(6,'general');