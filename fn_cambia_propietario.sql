
CREATE OR REPLACE FUNCTION fn_cambia_propietario(name, boolean, boolean) RETURNS void AS
$BODY$
DECLARE
p_propietario ALIAS FOR $1;
p_debug ALIAS FOR $2;
p_dryrun ALIAS FOR $3;
v_i integer := 0;
v_sql text;

--#################################################################################################
--	CURSORES
--#################################################################################################
-- ESQUEMAS
pesquemas CURSOR FOR
	SELECT quote_ident(nspname) as nombre_esquema
	FROM pg_namespace n
	INNER JOIN pg_roles h on n.nspowner = h.oid AND h.rolname <> p_propietario
	WHERE nspname NOT LIKE 'pg_%'
	AND nspname NOT IN ('information_schema','symmetricds', 'symmetricds_central', 'symmetricdscentral')
	ORDER BY 1 ASC;
-- TABLAS
ptablas CURSOR FOR
	SELECT quote_ident(schemaname) || '.' || quote_ident(tablename) as nombre_tabla FROM pg_tables
	WHERE schemaname NOT IN ('pg_catalog', 'information_schema', 'symmetricds', 'symmetricds_central', 'symmetricdscentral')
	AND schemaname NOT LIKE 'pg_%'
	AND tablename NOT LIKE 'pg_%'
	AND tableowner <> p_propietario
	ORDER BY 1 ASC;
-- FUNCIONES
pfunciones CURSOR FOR
	SELECT quote_ident(b.nspname) || '.' || quote_ident(a.proname) || '(' || pg_catalog.oidvectortypes(a.proargtypes) || ')' as nombre_function 
	FROM pg_proc a 
	INNER JOIN pg_namespace b on a.pronamespace = b.oid 
	INNER JOIN pg_roles h on a.proowner = h.oid AND h.rolname <> p_propietario
	WHERE b.nspname NOT IN ('pg_catalog', 'information_schema', 'symmetricds', 'symmetricds_central', 'symmetricdscentral') AND proisagg = 'f'
	AND a.proname not like 'fsym_%' AND a.proname not like 'dblink%' AND a.proname <> 'fn_cambia_propietario'
	ORDER BY 1 ASC;
-- SECUENCIAS
psecuencias CURSOR FOR
	SELECT quote_ident(n.nspname) || '.' || quote_ident(c.relname) as nombre_secuencia
	FROM pg_class c
	INNER JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
	INNER JOIN pg_roles h on c.relowner = h.oid AND h.rolname <> p_propietario
	WHERE c.relkind = 'S'
	AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'symmetricds', 'symmetricds_central', 'symmetricdscentral')
	ORDER BY 1 ASC;

-- TIPOS
ptipos CURSOR FOR
	SELECT quote_ident(n.nspname) || '.' || quote_ident(t.typname) as nombre_tipo
	FROM pg_type t
	INNER JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
	INNER JOIN pg_roles h on t.typowner = h.oid AND h.rolname <> p_propietario
	WHERE (t.typrelid = 0 OR (SELECT c.relkind = 'c' FROM pg_catalog.pg_class c WHERE c.oid = t.typrelid)) 
	AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_type el WHERE el.oid = t.typelem AND el.typarray = t.oid)
	AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'symmetricds', 'symmetricds_central', 'symmetricdscentral') ORDER BY 1 ASC;

BEGIN
--#################################################################################################
--	COMPROBAR SI EXISTE EL LOGIN
--#################################################################################################
	IF NOT EXISTS (SELECT 1 FROM pg_user WHERE usename = p_propietario) THEN                     
		RAISE EXCEPTION 'Login role no existente --> %', p_propietario
			USING HINT = 'Por favor verifique el login e intente nuevamente.';
	END IF;

--#################################################################################################
--	CAMBIAR EL PROPIETARIO A LOS ESQUEMAS
--#################################################################################################
	v_i = 0;
	if (p_debug) THEN
	RAISE NOTICE '###################################################';
	RAISE NOTICE ' INICIANDO A CAMBIAR EL PROPIETARIO DE LOS ESQUEMAS';
	RAISE NOTICE '###################################################';
	END IF;
	FOR resquema IN pesquemas LOOP
		v_sql = 'ALTER SCHEMA ' || resquema.nombre_esquema || ' OWNER TO ' || quote_ident(p_propietario) || ';';
		if (p_debug) THEN RAISE NOTICE '%', v_sql; END IF;
		if (p_dryrun = false) THEN EXECUTE v_sql; END IF;
		v_i = v_i + 1;
	END LOOP;
	if (p_debug) THEN
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	RAISE NOTICE ' ESQUEMAS CON EL PROPIETARIO = % TOTAL = %', p_propietario, CAST(v_i AS VARCHAR);
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	END IF;

--#################################################################################################
--	CAMBIAR EL PROPIETARIO A LAS TABLAS
--#################################################################################################
	v_i = 0;
	if (p_debug) THEN
	RAISE NOTICE '##################################################';
	RAISE NOTICE ' INICIANDO A CAMBIAR EL PROPIETARIO DE LAS TABLAS';
	RAISE NOTICE '##################################################';
	END IF;
	FOR rtables IN  ptablas LOOP
		v_sql = 'ALTER TABLE ' || rtables.nombre_tabla || ' OWNER TO ' || quote_ident(p_propietario) || ';';
		if (p_debug) THEN RAISE NOTICE '%', v_sql; END IF;
		if (p_dryrun = false) THEN EXECUTE v_sql; END IF;
		v_i = v_i + 1;
	END LOOP;
	if (p_debug) THEN
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	RAISE NOTICE ' TABLAS CON EL PROPIETARIO = % TOTAL = %', p_propietario, CAST(v_i AS VARCHAR);
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	END IF;

--#################################################################################################
	--  CAMBIAR EL PROPIETARIO A LAS FUNCIONES
--#################################################################################################
	v_i = 0;
	if (p_debug) THEN
	RAISE NOTICE '##################################################';
	RAISE NOTICE ' INICIANDO A CAMBIAR EL PROPIETARIO DE LAS FUNCIONES';
	RAISE NOTICE '##################################################';
	END IF;
	FOR rfunction IN  pfunciones LOOP
		v_sql = 'ALTER FUNCTION ' || rfunction.nombre_function || ' OWNER TO ' || quote_ident(p_propietario) || ';';
		if (p_debug) THEN RAISE NOTICE '%', v_sql; END IF;
		if (p_dryrun = false) THEN EXECUTE v_sql; END IF;
		v_i = v_i + 1;
	END LOOP;
	if (p_debug) THEN
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	RAISE NOTICE ' FUNCIONES CON EL PROPIETARIO = % TOTAL = %', p_propietario, CAST(v_i AS VARCHAR);
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	END IF;

--#################################################################################################
--  CAMBIAR EL PROPIETARIO A LAS SECUENCIAS
--#################################################################################################
	v_i = 0;
	if (p_debug) THEN
	RAISE NOTICE '##################################################';
	RAISE NOTICE ' INICIANDO A CAMBIAR EL PROPIETARIO DE LAS SECUENCIAS';
	RAISE NOTICE '##################################################';
	END IF;
	FOR rsecuencias IN  psecuencias LOOP
		v_sql = 'ALTER SEQUENCE ' || rsecuencias.nombre_secuencia || ' OWNER TO ' || quote_ident(p_propietario) || ';'; 			   
		if (p_debug) THEN RAISE NOTICE '%', v_sql; END IF;
		if (p_dryrun = false) THEN EXECUTE v_sql; END IF;
		v_i = v_i + 1;
	END LOOP;
	if (p_debug) THEN
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	RAISE NOTICE ' SECUENCIAS CON EL PROPIETARIO = % TOTAL = %', p_propietario, CAST(v_i AS VARCHAR);
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	END IF;

--#################################################################################################
--  CAMBIAR EL PROPIETARIO A LOS TIPOS
--#################################################################################################
	v_i = 0;
	if (p_debug) THEN
	RAISE NOTICE '##################################################';
	RAISE NOTICE ' INICIANDO A CAMBIAR EL PROPIETARIO DE LOS TIPOS';
	RAISE NOTICE '##################################################';
	END IF;
	FOR rtipos IN  ptipos LOOP                
		v_sql = 'ALTER TYPE ' || rtipos.nombre_tipo || ' OWNER TO ' || quote_ident(p_propietario) || ';'; 			   
		if (p_debug) THEN RAISE NOTICE '%', v_sql; END IF;
		if (p_dryrun = false) THEN EXECUTE v_sql; END IF;
		v_i = v_i + 1;
	END LOOP;
	if (p_debug) THEN
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	RAISE NOTICE '  TIPOS CON EL PROPIETARIO = % TOTAL = %', p_propietario, CAST(v_i AS VARCHAR);
	RAISE NOTICE '@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@';
	END IF;
	
--####
END;
$BODY$
  LANGUAGE 'plpgsql' VOLATILE
  COST 100;

SELECT fn_cambia_propietario('postgres', true, true);
DROP FUNCTION IF EXISTS fn_cambia_propietario(name, boolean, boolean);
