CREATE OR REPLACE FUNCTION fn_change_owner(name, boolean = true, boolean = true) RETURNS void AS
$BODY$
DECLARE
p_owner ALIAS FOR $1;
p_debug ALIAS FOR $2;
p_dryrun ALIAS FOR $3;
v_i integer := 0;
v_sql text;

--#################################################################################################
--	CURSORS
--#################################################################################################

-- SCHEMAS
pesquemas CURSOR FOR
  SELECT quote_ident(n.nspname) AS schema_name
  FROM pg_catalog.pg_namespace n
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
    AND pg_catalog.pg_get_userbyid(n.nspowner) <> p_owner
  ORDER BY 1;

-- TABLES
ptablas CURSOR FOR
	SELECT quote_ident(n.nspname) || '.' || quote_ident(c.relname) as table_name
	FROM pg_class c
	  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
	WHERE c.relkind = 'r'
  	AND n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
    AND c.relname !~ '^pg_'
    AND pg_catalog.pg_get_userbyid(c.relowner) <> p_owner
	ORDER BY 1;

pforeign CURSOR FOR
	SELECT quote_ident(n.nspname) || '.' || quote_ident(c.relname) as table_name
	FROM pg_class c
		JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
	WHERE c.relkind = 'f'
  	AND n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
    AND c.relname !~ '^pg_'
    AND pg_catalog.pg_get_userbyid(c.relowner) <> p_owner
	ORDER BY 1;

-- FUNCTIONS
pfunciones CURSOR FOR
	SELECT quote_ident(n.nspname) || '.' || quote_ident(p.proname) || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')' as function_name
	FROM pg_proc p
  	JOIN pg_namespace n on p.pronamespace = n.oid
	WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
    AND p.proname <> 'fn_change_owner'
    AND pg_catalog.pg_get_userbyid(p.proowner) <> p_owner
	ORDER BY 1;

proutines CURSOR FOR
	SELECT quote_ident(n.nspname) || '.' || quote_ident(p.proname) || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')' as function_name
	FROM pg_proc p
  	JOIN pg_namespace n on p.pronamespace = n.oid
	WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
    AND p.proname <> 'fn_change_owner'
    AND pg_catalog.pg_get_userbyid(p.proowner) <> p_owner
	ORDER BY 1;

-- SEQUENCES
psecuencias CURSOR FOR
	SELECT quote_ident(n.nspname) || '.' || quote_ident(c.relname) as sequence_name
	FROM pg_class c
	  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
	WHERE c.relkind = 'S'
  	AND n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
    AND c.relname !~ '^pg_'
    AND pg_catalog.pg_get_userbyid(c.relowner) <> p_owner
	ORDER BY 1;

-- TYPES
ptipos CURSOR FOR
	SELECT quote_ident(n.nspname) || '.' || quote_ident(t.typname) as type_name
	FROM pg_type t
	  JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
	WHERE (t.typrelid = 0 OR (SELECT c.relkind = 'c' FROM pg_catalog.pg_class c WHERE c.oid = t.typrelid))
  	AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_type el WHERE el.oid = t.typelem AND el.typarray = t.oid)
	  AND n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
    AND t.typname !~ '^pg_'
    AND pg_catalog.pg_get_userbyid(t.typowner) <> p_owner
  ORDER BY 1;

-- VIEWS
pvistas CURSOR FOR
	SELECT quote_ident(n.nspname) || '.' || quote_ident(c.relname) as view_name
	FROM pg_class c
	  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
	WHERE c.relkind IN ('v', 'm')
  	AND n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
    AND c.relname !~ '^pg_'
    AND pg_catalog.pg_get_userbyid(c.relowner) <> p_owner
	ORDER BY 1;

BEGIN
--#################################################################################################
--	Check login name
--#################################################################################################
	IF NOT EXISTS (SELECT 1 FROM pg_user WHERE usename = p_owner) THEN
		RAISE EXCEPTION 'Login role does not exists --> %', p_owner
			USING HINT = 'Please verify the login name and try again.';
	END IF;

--#################################################################################################
--	CAMBIAR EL PROPIETARIO A LOS ESQUEMAS
--#################################################################################################
	v_i = 0;
	if (p_debug) THEN
	RAISE NOTICE '###################################################';
	RAISE NOTICE ' CHANGING OWNER OF SCHEMAS ';
	RAISE NOTICE '###################################################';
	END IF;
	FOR resquema IN pesquemas LOOP
		v_sql = 'ALTER SCHEMA ' || resquema.schema_name || ' OWNER TO ' || quote_ident(p_owner) || ';';
		if (p_debug) THEN RAISE NOTICE '%', v_sql; END IF;
		if (p_dryrun = false) THEN EXECUTE v_sql; END IF;
		v_i = v_i + 1;
	END LOOP;
	if (p_debug) THEN
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	RAISE NOTICE ' SCHEMAS WITH OWNER = % TOTAL = %', p_owner, CAST(v_i AS VARCHAR);
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	END IF;

--#################################################################################################
--	CAMBIAR EL PROPIETARIO A LAS TABLAS
--#################################################################################################
	v_i = 0;
	if (p_debug) THEN
	RAISE NOTICE '##################################################';
	RAISE NOTICE ' CHANGING OWNER OF TABLES';
	RAISE NOTICE '##################################################';
	END IF;
	FOR rtables IN  ptablas LOOP
		v_sql = 'ALTER TABLE ' || rtables.table_name || ' OWNER TO ' || quote_ident(p_owner) || ';';
		if (p_debug) THEN RAISE NOTICE '%', v_sql; END IF;
		if (p_dryrun = false) THEN EXECUTE v_sql; END IF;
		v_i = v_i + 1;
	END LOOP;
	if (p_debug) THEN
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	RAISE NOTICE ' TABLES WITH OWNER = % TOTAL = %', p_owner, CAST(v_i AS VARCHAR);
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	END IF;

--#################################################################################################
--	CAMBIAR EL PROPIETARIO A LAS TABLAS FORANEAS
--#################################################################################################
	v_i = 0;
	if (p_debug) THEN
	RAISE NOTICE '##################################################';
	RAISE NOTICE ' CHANGING OWNER OF TABLES';
	RAISE NOTICE '##################################################';
	END IF;
	FOR rtables IN  ptablas LOOP
		v_sql = 'ALTER FOREIGN TABLE ' || rtables.table_name || ' OWNER TO ' || quote_ident(p_owner) || ';';
		if (p_debug) THEN RAISE NOTICE '%', v_sql; END IF;
		if (p_dryrun = false) THEN EXECUTE v_sql; END IF;
		v_i = v_i + 1;
	END LOOP;
	if (p_debug) THEN
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	RAISE NOTICE ' TABLES WITH OWNER = % TOTAL = %', p_owner, CAST(v_i AS VARCHAR);
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	END IF;

--#################################################################################################
	--  CAMBIAR EL PROPIETARIO A LAS FUNCIONES
--#################################################################################################
	v_i = 0;
	if (p_debug) THEN
	RAISE NOTICE '##################################################';
	RAISE NOTICE ' CHANGING OWNER OF FUNCTIONS ';
	RAISE NOTICE '##################################################';
	END IF;
	FOR rfunction IN  pfunciones LOOP
		v_sql = 'ALTER FUNCTION ' || rfunction.function_name || ' OWNER TO ' || quote_ident(p_owner) || ';';
		if (p_debug) THEN RAISE NOTICE '%', v_sql; END IF;
		if (p_dryrun = false) THEN
      BEGIN
        EXECUTE v_sql;
        EXCEPTION
        WHEN undefined_function THEN
          v_sql = 'ALTER FUNCTION ' || rfunction.function_name || ' OWNER TO ' || quote_ident(p_owner) || ';';
          EXECUTE v_sql;
      END;
    END IF;
		v_i = v_i + 1;
	END LOOP;
	if (p_debug) THEN
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	RAISE NOTICE ' FUNCTIONS WITH OWNER = % TOTAL = %', p_owner, CAST(v_i AS VARCHAR);
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	END IF;

--#################################################################################################
--  CAMBIAR EL PROPIETARIO A LAS SECUENCIAS
--#################################################################################################
	v_i = 0;
	if (p_debug) THEN
	RAISE NOTICE '##################################################';
	RAISE NOTICE ' CHANGING OWNER OF SEQUENCES ';
	RAISE NOTICE '##################################################';
	END IF;
	FOR rsecuencias IN  psecuencias LOOP
		v_sql = 'ALTER SEQUENCE ' || rsecuencias.sequence_name || ' OWNER TO ' || quote_ident(p_owner) || ';';
		if (p_debug) THEN RAISE NOTICE '%', v_sql; END IF;
		if (p_dryrun = false) THEN EXECUTE v_sql; END IF;
		v_i = v_i + 1;
	END LOOP;
	if (p_debug) THEN
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	RAISE NOTICE ' SEQUENCES WITH OWNER = % TOTAL = %', p_owner, CAST(v_i AS VARCHAR);
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	END IF;

--#################################################################################################
--  CAMBIAR EL PROPIETARIO A LOS TIPOS
--#################################################################################################
	v_i = 0;
	if (p_debug) THEN
	RAISE NOTICE '##################################################';
	RAISE NOTICE ' CHANGING OWNER OF TYPES ';
	RAISE NOTICE '##################################################';
	END IF;
	FOR rtipos IN  ptipos LOOP
		v_sql = 'ALTER TYPE ' || rtipos.type_name || ' OWNER TO ' || quote_ident(p_owner) || ';';
		if (p_debug) THEN RAISE NOTICE '%', v_sql; END IF;
		if (p_dryrun = false) THEN EXECUTE v_sql; END IF;
		v_i = v_i + 1;
	END LOOP;
	if (p_debug) THEN
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	RAISE NOTICE '  TYPES WITH OWNER = % TOTAL = %', p_owner, CAST(v_i AS VARCHAR);
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	END IF;

--#################################################################################################
--  CAMBIAR EL PROPIETARIO A LAS VISTAS
--#################################################################################################
	v_i = 0;
	if (p_debug) THEN
	RAISE NOTICE '##################################################';
	RAISE NOTICE ' CHANGING OWNER OF VIEWS ';
	RAISE NOTICE '##################################################';
	END IF;
	FOR rvistas IN  pvistas LOOP
		v_sql = 'ALTER VIEW ' || rvistas.view_name || ' OWNER TO ' || quote_ident(p_owner) || ';';
		if (p_debug) THEN RAISE NOTICE '%', v_sql; END IF;
		if (p_dryrun = false) THEN EXECUTE v_sql; END IF;
		v_i = v_i + 1;
	END LOOP;
	if (p_debug) THEN
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	RAISE NOTICE '  VIEWS WITH OWNER = % TOTAL = %', p_owner, CAST(v_i AS VARCHAR);
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	END IF;

--####
END;
$BODY$
  LANGUAGE 'plpgsql';

SELECT fn_change_owner('ongres', true, true);
DROP FUNCTION IF EXISTS fn_change_owner(name, boolean, boolean);

