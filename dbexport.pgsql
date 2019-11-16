--
-- PostgreSQL database dump
--

-- Dumped from database version 11.4
-- Dumped by pg_dump version 11.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry, geography, and raster spatial types and functions';


--
-- Name: pgrouting; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS pgrouting WITH SCHEMA public;


--
-- Name: EXTENSION pgrouting; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgrouting IS 'pgRouting Extension';


--
-- Name: pgr_createtopology3d(text, text, text, double precision, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.pgr_createtopology3d(edge_table text, f_zlev text, t_zlev text, tolerance double precision, the_geom text DEFAULT 'the_geom'::text, id text DEFAULT 'id'::text, source text DEFAULT 'source'::text, target text DEFAULT 'target'::text, rows_where text DEFAULT 'true'::text) RETURNS character varying
    LANGUAGE plpgsql STRICT
    AS $$

  DECLARE
    points      RECORD;
    sridinfo    RECORD;
    source_id   BIGINT;
    target_id   BIGINT;
    totcount    BIGINT;
    rowcount    BIGINT;
    srid        INTEGER;
    sql         TEXT;
    sname       TEXT;
    tname       TEXT;
    tabname     TEXT;
    vname       TEXT;
    vertname    TEXT;
    gname       TEXT;
    idname      TEXT;
    sourcename  TEXT;
    targetname  TEXT;
    notincluded INTEGER;
    i           INTEGER;
    naming      RECORD;
    flag        BOOLEAN;
    query       TEXT;
    sourcetype  TEXT;
    targettype  TEXT;
    debuglevel  TEXT;

  BEGIN
    RAISE NOTICE 'PROCESSING:';
    RAISE NOTICE 'pgr_createTopology(''%'',%,''%'',''%'',''%'',''%'',''%'',''%'',''%'')', edge_table, f_zlev, t_zlev, tolerance, the_geom, id, source, target, rows_where;
    RAISE NOTICE 'Performing checks, pelase wait .....';
    EXECUTE 'show client_min_messages'
    INTO debuglevel;


    BEGIN
      RAISE DEBUG 'Checking % exists', edge_table;
      EXECUTE 'select * from pgr_getTableName(' || quote_literal(edge_table) || ')'
      INTO naming;
      sname=naming.sname;
      tname=naming.tname;
      IF sname IS NULL OR tname IS NULL
      THEN
        RAISE NOTICE '-------> % not found', edge_table;
        RETURN 'FAIL';
      ELSE
        RAISE DEBUG '  -----> OK';
      END IF;

      tabname=sname || '.' || tname;
      vname=tname || '_vertices_pgr';
      vertname= sname || '.' || vname;
      rows_where = ' AND (' || rows_where || ')';
    END;

    BEGIN
      RAISE DEBUG 'Checking id column "%" columns in  % ', id, tabname;
      EXECUTE 'select pgr_getColumnName(' || quote_literal(tabname) || ',' || quote_literal(the_geom) || ')'
      INTO gname;
      EXECUTE 'select pgr_getColumnName(' || quote_literal(tabname) || ',' || quote_literal(id) || ')'
      INTO idname;
      IF idname IS NULL
      THEN
        RAISE NOTICE 'ERROR: id column "%"  not found in %', id, tabname;
        RETURN 'FAIL';
      END IF;
      RAISE DEBUG 'Checking geometry column "%" column  in  % ', the_geom, tabname;
      IF gname IS NOT NULL
      THEN
        BEGIN
          RAISE DEBUG 'Checking the SRID of the geometry "%"', gname;
          query= 'SELECT ST_SRID(' || quote_ident(gname) || ') as srid '
                 || ' FROM ' || pgr_quote_ident(tabname)
                 || ' WHERE ' || quote_ident(gname)
                 || ' IS NOT NULL LIMIT 1';
          EXECUTE QUERY
          INTO sridinfo;

          IF sridinfo IS NULL OR sridinfo.srid IS NULL
          THEN
            RAISE NOTICE 'ERROR: Can not determine the srid of the geometry "%" in table %', the_geom, tabname;
            RETURN 'FAIL';
          END IF;
          srid := sridinfo.srid;
          RAISE DEBUG '  -----> SRID found %', srid;
          EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE 'ERROR: Can not determine the srid of the geometry "%" in table %', the_geom, tabname;
          RETURN 'FAIL';
        END;
      ELSE
        RAISE NOTICE 'ERROR: Geometry column "%"  not found in %', the_geom, tabname;
        RETURN 'FAIL';
      END IF;
    END;

    BEGIN
      RAISE DEBUG 'Checking source column "%" and target column "%"  in  % ', source, target, tabname;
      EXECUTE 'select  pgr_getColumnName(' || quote_literal(tabname) || ',' || quote_literal(source) || ')'
      INTO sourcename;
      EXECUTE 'select  pgr_getColumnName(' || quote_literal(tabname) || ',' || quote_literal(target) || ')'
      INTO targetname;
      IF sourcename IS NOT NULL AND targetname IS NOT NULL
      THEN
--check that the are integer
        EXECUTE 'select data_type  from information_schema.columns where table_name = ' || quote_literal(tname) ||
                ' and table_schema=' || quote_literal(sname) || ' and column_name=' || quote_literal(sourcename)
        INTO sourcetype;
        EXECUTE 'select data_type  from information_schema.columns where table_name = ' || quote_literal(tname) ||
                ' and table_schema=' || quote_literal(sname) || ' and column_name=' || quote_literal(targetname)
        INTO targettype;
        IF sourcetype NOT IN ('integer', 'smallint', 'bigint')
        THEN
          RAISE NOTICE 'ERROR: source column "%" is not of integer type', sourcename;
          RETURN 'FAIL';
        END IF;
        IF targettype NOT IN ('integer', 'smallint', 'bigint')
        THEN
          RAISE NOTICE 'ERROR: target column "%" is not of integer type', targetname;
          RETURN 'FAIL';
        END IF;
        RAISE DEBUG '  ------>OK ';
      END IF;
      IF sourcename IS NULL
      THEN
        RAISE NOTICE 'ERROR: source column "%"  not found in %', source, tabname;
        RETURN 'FAIL';
      END IF;
      IF targetname IS NULL
      THEN
        RAISE NOTICE 'ERROR: target column "%"  not found in %', target, tabname;
        RETURN 'FAIL';
      END IF;
    END;


    IF sourcename = targetname
    THEN
      RAISE NOTICE 'ERROR: source and target columns have the same name "%" in %', target, tabname;
      RETURN 'FAIL';
    END IF;
    IF sourcename = idname
    THEN
      RAISE NOTICE 'ERROR: source and id columns have the same name "%" in %', target, tabname;
      RETURN 'FAIL';
    END IF;
    IF targetname = idname
    THEN
      RAISE NOTICE 'ERROR: target and id columns have the same name "%" in %', target, tabname;
      RETURN 'FAIL';
    END IF;


    BEGIN
      RAISE DEBUG 'Checking "%" column in % is indexed', idname, tabname;
      IF (pgr_isColumnIndexed(tabname, idname))
      THEN
        RAISE DEBUG '  ------>OK';
      ELSE
        RAISE DEBUG ' ------> Adding  index "%_%_idx".', tabname, idname;
        SET client_min_messages TO WARNING;
        EXECUTE 'create  index ' || pgr_quote_ident(tname || '_' || idname || '_idx') || '
                         on ' || pgr_quote_ident(tabname) || ' using btree(' || quote_ident(idname) || ')';
        EXECUTE 'set client_min_messages  to ' || debuglevel;
      END IF;
    END;

    BEGIN
      RAISE DEBUG 'Checking "%" column in % is indexed', sourcename, tabname;
      IF (pgr_isColumnIndexed(tabname, sourcename))
      THEN
        RAISE DEBUG '  ------>OK';
      ELSE
        RAISE DEBUG ' ------> Adding  index "%_%_idx".', tabname, sourcename;
        SET client_min_messages TO WARNING;
        EXECUTE 'create  index ' || pgr_quote_ident(tname || '_' || sourcename || '_idx') || '
                         on ' || pgr_quote_ident(tabname) || ' using btree(' || quote_ident(sourcename) || ')';
        EXECUTE 'set client_min_messages  to ' || debuglevel;
      END IF;
    END;

    BEGIN
      RAISE DEBUG 'Checking "%" column in % is indexed', targetname, tabname;
      IF (pgr_isColumnIndexed(tabname, targetname))
      THEN
        RAISE DEBUG '  ------>OK';
      ELSE
        RAISE DEBUG ' ------> Adding  index "%_%_idx".', tabname, targetname;
        SET client_min_messages TO WARNING;
        EXECUTE 'create  index ' || pgr_quote_ident(tname || '_' || targetname || '_idx') || '
                         on ' || pgr_quote_ident(tabname) || ' using btree(' || quote_ident(targetname) || ')';
        EXECUTE 'set client_min_messages  to ' || debuglevel;
      END IF;
    END;

    BEGIN
      RAISE DEBUG 'Checking "%" column in % is indexed', gname, tabname;
      IF (pgr_iscolumnindexed(tabname, gname))
      THEN
        RAISE DEBUG '  ------>OK';
      ELSE
        RAISE DEBUG ' ------> Adding unique index "%_%_gidx".', tabname, gname;
        SET client_min_messages TO WARNING;
        EXECUTE 'CREATE INDEX '
                || quote_ident(tname || '_' || gname || '_gidx')
                || ' ON ' || pgr_quote_ident(tabname)
                || ' USING gist (' || quote_ident(gname) || ')';
        EXECUTE 'set client_min_messages  to ' || debuglevel;
      END IF;
    END;
    gname=quote_ident(gname);
    idname=quote_ident(idname);
    sourcename=quote_ident(sourcename);
    targetname=quote_ident(targetname);


    BEGIN
      RAISE DEBUG 'initializing %', vertname;
      EXECUTE 'select * from pgr_getTableName(' || quote_literal(vertname) || ')'
      INTO naming;
      IF sname = naming.sname AND vname = naming.tname
      THEN
        EXECUTE 'TRUNCATE TABLE ' || pgr_quote_ident(vertname) || ' RESTART IDENTITY';
        EXECUTE 'SELECT DROPGEOMETRYCOLUMN(' || quote_literal(sname) || ',' || quote_literal(vname) || ',' ||
                quote_literal('the_geom') || ')';
      ELSE
        SET client_min_messages TO WARNING;
        EXECUTE 'CREATE TABLE ' || pgr_quote_ident(vertname) ||
                ' (id bigserial PRIMARY KEY,cnt integer,chk integer,ein integer,eout integer)';
      END IF;
      EXECUTE 'select addGeometryColumn(' || quote_literal(sname) || ',' || quote_literal(vname) || ',' ||
              quote_literal('the_geom') || ',' || srid || ', ' || quote_literal('POINT') || ', 3)';
      EXECUTE 'CREATE INDEX ' || quote_ident(vname || '_the_geom_idx') || ' ON ' || pgr_quote_ident(vertname) ||
              '  USING GIST (the_geom)';
      EXECUTE 'set client_min_messages  to ' || debuglevel;
      RAISE DEBUG '  ------>OK';
    END;


    BEGIN
      sql = 'select count(*) from ( select * from ' || pgr_quote_ident(tabname) || ' WHERE true' || rows_where ||
            ' limit 1 ) foo';
      EXECUTE sql
      INTO i;
      sql = 'select count(*) from ' || pgr_quote_ident(tabname) || ' WHERE (' || gname || ' IS NOT NULL AND ' ||
            idname || ' IS NOT NULL)=false ' || rows_where;
      EXECUTE SQL
      INTO notincluded;
      EXCEPTION WHEN OTHERS THEN BEGIN
      RAISE NOTICE 'Got %', SQLERRM;
      RAISE NOTICE 'ERROR: Condition is not correct, please execute the following query to test your condition';
      RAISE NOTICE '%', sql;
      RETURN 'FAIL';
    END;
    END;


    BEGIN
      RAISE NOTICE 'Creating Topology, Please wait...';
      EXECUTE 'UPDATE ' || pgr_quote_ident(tabname) ||
              ' SET ' || sourcename || ' = NULL,' || targetname || ' = NULL';
      rowcount := 0;
      FOR points IN EXECUTE 'SELECT ' || idname || '::bigint AS id,
                            coalesce(' || f_zlev || '::float,0.0) AS f_zlev,
                            coalesce(' || t_zlev || '::float,0.0) AS t_zlev,'
                            || ' PGR_StartPoint(' || gname || ') AS source,'
                            || ' PGR_EndPoint(' || gname || ') AS target'
                            || ' FROM ' || pgr_quote_ident(tabname)
                            || ' WHERE ' || gname || ' IS NOT NULL AND '
                            || idname || ' IS NOT NULL ' || rows_where
                            || ' ORDER BY ' || idname
      LOOP

        rowcount := rowcount + 1;
        IF rowcount % 1000 = 0
        THEN
          RAISE NOTICE '% edges processed', rowcount;
        END IF;


        source_id := pgr_pointToIdZ(points.source, tolerance, vertname, srid, points.f_zlev);
        target_id := pgr_pointToIdZ(points.target, tolerance, vertname, srid, points.t_zlev);
        BEGIN
          sql := 'UPDATE ' || pgr_quote_ident(tabname) ||
                 ' SET ' || sourcename || ' = ' || source_id :: TEXT || ',' || targetname || ' = ' || target_id :: TEXT
                 ||
                 ' WHERE ' || idname || ' =  ' || points.id :: TEXT;

          IF sql IS NULL
          THEN
            RAISE NOTICE 'WARNING: UPDATE % SET source = %, target = % WHERE % = % ', tabname, source_id :: TEXT, target_id :: TEXT, idname, points.id :: TEXT;
          ELSE
            EXECUTE sql;
          END IF;
          EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE '%', SQLERRM;
          RAISE NOTICE '%', sql;
          RETURN 'FAIL';
        END;
      END LOOP;
      RAISE NOTICE '-------------> TOPOLOGY CREATED FOR  % edges', rowcount;
      RAISE NOTICE 'Rows with NULL geometry or NULL id: %', notincluded;
      RAISE NOTICE 'Vertices table for table % is: %', pgr_quote_ident(tabname), pgr_quote_ident(vertname);
      RAISE NOTICE '----------------------------------------------';
    END;
    RETURN 'OK';

  END;


  $$;


ALTER FUNCTION public.pgr_createtopology3d(edge_table text, f_zlev text, t_zlev text, tolerance double precision, the_geom text, id text, source text, target text, rows_where text) OWNER TO postgres;

--
-- Name: pgr_pointtoidz(public.geometry, double precision, text, integer, double precision); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.pgr_pointtoidz(point public.geometry, tolerance double precision, vertname text, srid integer, zlev double precision) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
  DECLARE
    rec RECORD;
    pid BIGINT;
    pnt geometry;
  BEGIN
    pnt := st_translate(
        st_force_3d(point), 0.0, 0.0, coalesce(zlev :: FLOAT, 0.0));
    EXECUTE
    'SELECT
      id,
      the_geom
    FROM
      ' || vertname || '
    WHERE
      ST_expand(ST_GeomFromText(st_astext(' || quote_literal(pnt :: TEXT) || '),' || srid || '), ' || text(tolerance) || ') && the_geom AND
      ST_3DLength(ST_makeline(the_geom, ST_GeomFromText(st_astext(' || quote_literal(pnt :: TEXT) || '),' || srid ||
    '))) < ' || text(tolerance) || ' ORDER BY ST_3DLength(ST_makeline(the_geom, ST_GeomFromText(st_astext(' ||
    quote_literal(pnt :: TEXT) || '),' || srid ||
    '))) LIMIT 1'
    INTO rec;
    IF rec.id IS NOT NULL
    THEN
      pid := rec.id;
    ELSE
      EXECUTE 'INSERT INTO ' || pgr_quote_ident(vertname) || ' (the_geom) VALUES (' || quote_literal(pnt :: TEXT) ||
              ')';
      pid := lastval();
    END IF;
    RETURN pid;
  END;
  $$;


ALTER FUNCTION public.pgr_pointtoidz(point public.geometry, tolerance double precision, vertname text, srid integer, zlev double precision) OWNER TO postgres;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: edges; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.edges (
    level character varying(200),
    _area_id character varying(200),
    _length double precision,
    _id bigint NOT NULL,
    source bigint,
    target bigint,
    wheelchair boolean,
    geom public.geometry(GeometryZ,900916),
    f_zlev text,
    t_zlev text
);


ALTER TABLE public.edges OWNER TO postgres;

--
-- Name: edges_vertices_pgr; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.edges_vertices_pgr (
    id bigint NOT NULL,
    cnt integer,
    chk integer,
    ein integer,
    eout integer,
    the_geom public.geometry(PointZ,900916)
);


ALTER TABLE public.edges_vertices_pgr OWNER TO postgres;

--
-- Name: edges_vertices_pgr_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.edges_vertices_pgr_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.edges_vertices_pgr_id_seq OWNER TO postgres;

--
-- Name: edges_vertices_pgr_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.edges_vertices_pgr_id_seq OWNED BY public.edges_vertices_pgr.id;


--
-- Name: first_floor_edges; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.first_floor_edges (
    level character varying(200),
    _area_id character varying(200),
    _length double precision,
    _id bigint NOT NULL,
    source bigint,
    target bigint,
    geom public.geometry(GeometryZ,900916),
    f_zlev text,
    t_zlev text
);


ALTER TABLE public.first_floor_edges OWNER TO postgres;

--
-- Name: first_floor_edges_noded; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.first_floor_edges_noded (
    id bigint NOT NULL,
    old_id integer,
    sub_id integer,
    source bigint,
    target bigint,
    geom public.geometry(LineString,4326)
);


ALTER TABLE public.first_floor_edges_noded OWNER TO postgres;

--
-- Name: first_floor_edges_noded_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.first_floor_edges_noded_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.first_floor_edges_noded_id_seq OWNER TO postgres;

--
-- Name: first_floor_edges_noded_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.first_floor_edges_noded_id_seq OWNED BY public.first_floor_edges_noded.id;


--
-- Name: first_floor_edges_vertices_pgr; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.first_floor_edges_vertices_pgr (
    id bigint NOT NULL,
    cnt integer,
    chk integer,
    ein integer,
    eout integer,
    the_geom public.geometry(PointZ,900916)
);


ALTER TABLE public.first_floor_edges_vertices_pgr OWNER TO postgres;

--
-- Name: first_floor_edges_vertices_pgr_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.first_floor_edges_vertices_pgr_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.first_floor_edges_vertices_pgr_id_seq OWNER TO postgres;

--
-- Name: first_floor_edges_vertices_pgr_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.first_floor_edges_vertices_pgr_id_seq OWNED BY public.first_floor_edges_vertices_pgr.id;


--
-- Name: first_floor_rooms; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.first_floor_rooms (
    level character varying(200),
    _area_id character varying(200),
    _coordsys character varying(200),
    geom public.geometry(GeometryZ,900916)
);


ALTER TABLE public.first_floor_rooms OWNER TO postgres;

--
-- Name: rooms; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.rooms (
    level character varying(200),
    _area_id character varying(200) NOT NULL,
    geom public.geometry(GeometryZ,900916)
);


ALTER TABLE public.rooms OWNER TO postgres;

--
-- Name: second_floor_edges; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.second_floor_edges (
    level character varying(200),
    _area_id character varying(200),
    _length double precision,
    _id bigint NOT NULL,
    source bigint,
    target bigint,
    geom public.geometry(GeometryZ,900916)
);


ALTER TABLE public.second_floor_edges OWNER TO postgres;

--
-- Name: second_floor_edges_vertices_pgr; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.second_floor_edges_vertices_pgr (
    id bigint NOT NULL,
    cnt integer,
    chk integer,
    ein integer,
    eout integer,
    the_geom public.geometry(Point,4326)
);


ALTER TABLE public.second_floor_edges_vertices_pgr OWNER TO postgres;

--
-- Name: second_floor_edges_vertices_pgr_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.second_floor_edges_vertices_pgr_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.second_floor_edges_vertices_pgr_id_seq OWNER TO postgres;

--
-- Name: second_floor_edges_vertices_pgr_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.second_floor_edges_vertices_pgr_id_seq OWNED BY public.second_floor_edges_vertices_pgr.id;


--
-- Name: second_floor_rooms; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.second_floor_rooms (
    level character varying(200),
    _area_id character varying(200) NOT NULL,
    coord_sys character varying(200),
    geom public.geometry(GeometryZ,900916)
);


ALTER TABLE public.second_floor_rooms OWNER TO postgres;

--
-- Name: edges_vertices_pgr id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.edges_vertices_pgr ALTER COLUMN id SET DEFAULT nextval('public.edges_vertices_pgr_id_seq'::regclass);


--
-- Name: first_floor_edges_noded id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.first_floor_edges_noded ALTER COLUMN id SET DEFAULT nextval('public.first_floor_edges_noded_id_seq'::regclass);


--
-- Name: first_floor_edges_vertices_pgr id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.first_floor_edges_vertices_pgr ALTER COLUMN id SET DEFAULT nextval('public.first_floor_edges_vertices_pgr_id_seq'::regclass);


--
-- Name: second_floor_edges_vertices_pgr id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.second_floor_edges_vertices_pgr ALTER COLUMN id SET DEFAULT nextval('public.second_floor_edges_vertices_pgr_id_seq'::regclass);


--
-- Data for Name: edges; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.edges (level, _area_id, _length, _id, source, target, wheelchair, geom, f_zlev, t_zlev) FROM stdin;
first_floor	\N	0.604338199065438175	172	171	172	t	01020000A034BF0D000200000015AF5FB3E79052C0F8BDA57F49EC2AC09A9999999999E93F7FDC7F2D95B752C0F8BDA57F49EC2AC09A9999999999E93F	\N	\N
first_floor	\N	0.25	205	205	203	t	01020000A034BF0D000200000039548F320E0C51C0B8C98A2B7DAA33C09A9999999999E93F39548F320E1C51C0B8C98A2B7DAA33C09A9999999999E93F	\N	\N
second_floor	\N	0.114707788247855547	402	403	401	t	01020000A034BF0D0002000000D21849189D5047C0A03A7185218023C00000000000000840D21849189D5047C0A8FCC28A664523C00000000000000840	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035084216	3	1	2	t	01020000A034BF0D0003000000CCC6C444F70B3FC0283B51E7C38123C09A9999999999E93FCCC6C444F70B3FC0186282EF6F9E24C09A9999999999E93FC4C1243DDC6F3EC0286CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	\N	0.10867074331861204	4	3	1	t	01020000A034BF0D0002000000CCC6C444F70B3FC0680F4036204A23C09A9999999999E93FCCC6C444F70B3FC0283B51E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NB	5.5092697945310567	5	4	3	t	01020000A034BF0D000B00000000714B1FBF8C3FC0807E2ADAF67913C09A9999999999E93F0CFA8EA456763EC0505A1CC598D317C09A9999999999E93F0CFA8EA456763EC030870C00904218C09A9999999999E93F6487B2FCA8693EC0D0517E9F467518C09A9999999999E93F6487B2FCA8693EC0D0DD39D6DFE11FC09A9999999999E93F90152BD57D893EC0400B0E9C993020C09A9999999999E93F90152BD57D893EC0D862246FBA3121C09A9999999999E93F948FB2FCA8093FC0E85633BE103222C09A9999999999E93F948FB2FCA8093FC0189C803B7E7622C09A9999999999E93FCCC6C444F70B3FC0800AA5CB1A7B22C09A9999999999E93FCCC6C444F70B3FC0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.48042511641065744	6	2	5	t	01020000A034BF0D0002000000C4C1243DDC6F3EC0286CC2FEA5D625C09A9999999999E93F9C983119DFF43BC0386CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6N6	3.96763137403211941	7	6	7	t	01020000A034BF0D000A0000009C939111C4583BC0680F4036204A23C09A9999999999E93F9C939111C4583BC0780AA5CB1A7B22C09A9999999999E93FFC7637AD88593BC0B8435994917922C09A9999999999E93FFC7637AD88593BC038AF5A65FD2E22C09A9999999999E93F4C36644ED4D73BC0A0300123663221C09A9999999999E93F4C36644ED4D73BC008D9EA4F453120C09A9999999999E93F20A8EB75FFF73BC0C0EAB701DEE11FC09A9999999999E93F20A8EB75FFF73BC0E0440074487518C09A9999999999E93F2C812E8413EB3BC010A90BAD984118C09A9999999999E93F2C812E8413EB3BC0307C1B72A1D217C09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318697305	8	8	6	t	01020000A034BF0D00020000009C939111C4583BC0583B51E7C38123C09A9999999999E93F9C939111C4583BC0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035078176	9	5	8	t	01020000A034BF0D00030000009C983119DFF43BC0386CC2FEA5D625C09A9999999999E93F9C939111C4583BC0486282EF6F9E24C09A9999999999E93F9C939111C4583BC0583B51E7C38123C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.20000000000002882	10	5	9	t	01020000A034BF0D00030000009C983119DFF43BC0386CC2FEA5D625C09A9999999999E93F94983119DFF43BC0486CC2FEA5D625C09A9999999999E93F6465FEE5ABC13AC0486CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6N5	3.93373895941855523	11	10	11	t	01020000A034BF0D000600000068605EDE90253AC0F80D4036204A23C09A9999999999E93F68605EDE90253AC0800AA5CB1A7B22C09A9999999999E93FE47CB842CC243AC078435994917922C09A9999999999E93FE47CB842CC243AC010AE5A65FD2E22C09A9999999999E93FB02CD7C7B79639C0A80D986FD41221C09A9999999999E93FB02CD7C7B79639C05092C401C8C417C09A9999999999E93F	\N	\N
first_floor	\N	0.108670743319379426	12	12	10	t	01020000A034BF0D000200000068605EDE90253AC0683B51E7C38123C09A9999999999E93F68605EDE90253AC0F80D4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035076755	13	9	12	t	01020000A034BF0D00030000006465FEE5ABC13AC0486CC2FEA5D625C09A9999999999E93F68605EDE90253AC0506282EF6F9E24C09A9999999999E93F68605EDE90253AC0683B51E7C38123C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.610236572961170509	14	9	13	t	01020000A034BF0D00030000006465FEE5ABC13AC0486CC2FEA5D625C09A9999999999E93F6065FEE5ABC13AC0486CC2FEA5D625C09A9999999999E93F68B4326F73253AC0486CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.15999999999998238	15	13	14	t	01020000A034BF0D000200000068B4326F73253AC0486CC2FEA5D625C09A9999999999E93F4458A3AC7DFC38C0506CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.545763427053998385	16	14	15	t	01020000A034BF0D00020000004458A3AC7DFC38C0506CC2FEA5D625C09A9999999999E93F84CBBC85C67038C0506CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	1.78292440942558983	54	52	53	t	01020000A034BF0D000400000080F5B51E2CD5F0BFE088E89125971DC09A9999999999E93FC03593FF666FF2BFD038B1D996301DC09A9999999999E93FC03593FF666FF2BF802C0BADBDAB17C09A9999999999E93F00172739EF64F5BF4034A69E5BEE16C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6N0	3.96745883010850342	17	16	17	t	01020000A034BF0D000A00000094C61C7EABD437C0680F4036204A23C09A9999999999E93F94C61C7EABD437C0800AA5CB1A7B22C09A9999999999E93F5CE376E2E6D337C008445994917922C09A9999999999E93F5CE376E2E6D337C0E8AE5A65FD2E22C09A9999999999E93FCC9CAF4DC65537C0D021CC3BBC3221C09A9999999999E93FCC9CAF4DC65537C0386A0231423120C09A9999999999E93FAC41312CF33537C0F0670BDC37E31FC09A9999999999E93FAC41312CF33537C0308B10519E7218C09A9999999999E93F40084BD4A04237C0E070A9B0E73F18C09A9999999999E93F40084BD4A04237C080C0EE4E8ED117C09A9999999999E93F	\N	\N
first_floor	\N	0.10867074331878257	18	18	16	t	01020000A034BF0D000200000094C61C7EABD437C0883B51E7C38123C09A9999999999E93F94C61C7EABD437C0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035071559	19	15	18	t	01020000A034BF0D000300000084CBBC85C67038C0506CC2FEA5D625C09A9999999999E93F94C61C7EABD437C0806282EF6F9E24C09A9999999999E93F94C61C7EABD437C0883B51E7C38123C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.70000000000005969	20	15	19	t	01020000A034BF0D000300000084CBBC85C67038C0506CC2FEA5D625C09A9999999999E93F84CBBC85C67038C0586CC2FEA5D625C09A9999999999E93F4498895293BD35C0606CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NV	3.28707853436293451	21	20	21	t	01020000A034BF0D00050000005C93E94A782135C0680F4036204A23C09A9999999999E93F5C93E94A782135C078E80E2E742D22C09A9999999999E93F5C93E94A782135C0501D5B5E1B2C22C09A9999999999E93F88139A62CA7B33C0503B781B7FC11DC09A9999999999E93F88139A62CA7B33C0A0767CC5F1281CC09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318839413	22	22	20	t	01020000A034BF0D00020000005C93E94A782135C0A83B51E7C38123C09A9999999999E93F5C93E94A782135C0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035067119	23	19	22	t	01020000A034BF0D00030000004498895293BD35C0606CC2FEA5D625C09A9999999999E93F5C93E94A782135C0986282EF6F9E24C09A9999999999E93F5C93E94A782135C0A83B51E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NV	0.223892632226773969	24	21	23	t	01020000A034BF0D000300000088139A62CA7B33C0A0767CC5F1281CC09A9999999999E93FD8088D3A178933C060A1B065BEF31BC09A9999999999E93F88AC901499AF33C060A1B065BEF31BC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NV	0.17715025427540898	25	23	24	t	01020000A034BF0D000300000088AC901499AF33C060A1B065BEF31BC09A9999999999E93F9402C84064BD33C090F98D16EB2A1CC09A9999999999E93FA4A8C7233CD733C090F98D16EB2A1CC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NV	0.611457521901398238	26	23	25	t	01020000A034BF0D000300000088AC901499AF33C060A1B065BEF31BC09A9999999999E93FE0F5E5E5601D34C0007C5B209F3C1AC09A9999999999E93FE0F5E5E5601D34C010E4096880371AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NV	1.65995516342792482	27	21	26	t	01020000A034BF0D000200000088139A62CA7B33C0A0767CC5F1281CC09A9999999999E93FD0CE647C4E4F32C0C063A72C027717C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.73423657294600275	28	19	27	t	01020000A034BF0D00030000004498895293BD35C0606CC2FEA5D625C09A9999999999E93F4498895293BD35C0686CC2FEA5D625C09A9999999999E93FC043F5649C0133C0786CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.21999999999999886	29	27	28	t	01020000A034BF0D0002000000C043F5649C0133C0786CC2FEA5D625C09A9999999999E93F082570794AC931C0786CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.548763863374944094	30	28	29	t	01020000A034BF0D0002000000082570794AC931C0786CC2FEA5D625C09A9999999999E93F00B991AFCE3C31C0806CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NQ	3.96668080187922589	31	30	31	t	01020000A034BF0D000B00000024B4F1A7B3A030C0680F4036204A23C09A9999999999E93F24B4F1A7B3A030C0900AA5CB1A7B22C09A9999999999E93FDCD04B0CEF9F30C008445994917922C09A9999999999E93FDCD04B0CEF9F30C008AF5A65FD2E22C09A9999999999E93FEC65A2B3653530C020D907B4EA5921C09A9999999999E93FEC65A2B3653530C070089905205820C09A9999999999E93F00C3F0B9E00230C030856B242CE61FC09A9999999999E93F00C3F0B9E00230C0E0D47EF7372A1CC09A9999999999E93F00C3F0B9E00230C0B0D2CF2E5D6E18C09A9999999999E93F1C51D44F0B0F30C0409A41D7B23D18C09A9999999999E93F1C51D44F0B0F30C0F0521D0805D017C09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318938889	32	32	30	t	01020000A034BF0D000200000024B4F1A7B3A030C0E03B51E7C38123C09A9999999999E93F24B4F1A7B3A030C0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035061523	33	29	32	t	01020000A034BF0D000300000000B991AFCE3C31C0806CC2FEA5D625C09A9999999999E93F24B4F1A7B3A030C0D86282EF6F9E24C09A9999999999E93F24B4F1A7B3A030C0E03B51E7C38123C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	4.50285834674909236	34	29	33	t	01020000A034BF0D000400000000B991AFCE3C31C0806CC2FEA5D625C09A9999999999E93FFCB891AFCE3C31C0806CC2FEA5D625C09A9999999999E93FA089D96DE5D329C0A06CC2FEA5D625C09A9999999999E93F88D2CCD1059329C080B5B562C69525C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.15323592294051025	35	33	34	t	01020000A034BF0D000200000088D2CCD1059329C080B5B562C69525C09A9999999999E93F609E71E1904427C080B5B562C69525C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.81419711436426168	36	34	35	t	01020000A034BF0D0003000000609E71E1904427C080B5B562C69525C09A9999999999E93F4022306DFA9B26C080B5B562C69525C09A9999999999E93FB08896D3608224C0184F4FFC5FAF27C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	3.30212362160598616	37	35	36	t	01020000A034BF0D0002000000B08896D3608224C0184F4FFC5FAF27C09A9999999999E93F107B24C261CF1BC0184F4FFC5FAF27C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	10.1815012466548538	38	36	37	t	01020000A034BF0D0003000000107B24C261CF1BC0184F4FFC5FAF27C09A9999999999E93FB0AB285BDEA319C07067D1489E9926C09A9999999999E93FB0AB285BDEA319C0407B8399F92BFEBF9A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.0403556115579419838	39	37	38	t	01020000A034BF0D0002000000B0AB285BDEA319C0407B8399F92BFEBF9A9999999999E93FB0AB285BDEA319C0C0DB85ACAD86FDBF9A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.0453804721045685255	40	38	39	t	01020000A034BF0D0002000000B0AB285BDEA319C0C0DB85ACAD86FDBF9A9999999999E93FB0AB285BDEA319C0C0CCCCCCCCCCFCBF9A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kU	3.28566286245995709	41	40	41	t	01020000A034BF0D00050000006079F527AB7011C0C0DB85ACAD86FDBF9A9999999999E93F4061FDD216AC0FC0C0DB85ACAD86FDBF9A9999999999E93FA01447DF18D70EC0C0DB85ACAD86FDBF9A9999999999E93F808F772C8C7A0AC080D1E64694CDF4BF9A9999999999E93F00C3E64694CDF4BF80D1E64694CDF4BF9A9999999999E93F	\N	\N
first_floor	\N	0.249999999999801048	42	42	40	t	01020000A034BF0D00020000008078F527AB7012C0C0DB85ACAD86FDBF9A9999999999E93F6079F527AB7011C0C0DB85ACAD86FDBF9A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.79999999999999716	43	38	42	t	01020000A034BF0D0003000000B0AB285BDEA319C0C0DB85ACAD86FDBF9A9999999999E93F30416CE64A0B14C0C0DB85ACAD86FDBF9A9999999999E93F8078F527AB7012C0C0DB85ACAD86FDBF9A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kT	3.35773400212494488	44	43	44	t	01020000A034BF0D0007000000F05DA33F68DE20C0407B8399F92BFEBF9A9999999999E93F48C2DE1EB8AB21C0407B8399F92BFEBF9A9999999999E93FB0A684BA7CCC21C0407B8399F92BFEBF9A9999999999E93F48A3049220FD22C0C09683DDDAA6F4BF9A9999999999E93F90438D362AB326C0C09683DDDAA6F4BF9A9999999999E93F509860EFAACC26C080F0E816D5DAF3BF9A9999999999E93F1079B440D10C27C080F0E816D5DAF3BF9A9999999999E93F	\N	\N
first_floor	\N	0.224361194929997509	45	45	43	t	01020000A034BF0D000200000070EF2DC7886B20C0407B8399F92BFEBF9A9999999999E93FF05DA33F68DE20C0407B8399F92BFEBF9A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.79999999999999716	46	37	45	t	01020000A034BF0D0003000000B0AB285BDEA319C0407B8399F92BFEBF9A9999999999E93F2016E5CF713C1FC0407B8399F92BFEBF9A9999999999E93F70EF2DC7886B20C0407B8399F92BFEBF9A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.7728613987631876	47	36	46	t	01020000A034BF0D0003000000107B24C261CF1BC0184F4FFC5FAF27C09A9999999999E93F70DE9C754ABA1BC0681D93A2EBB927C09A9999999999E93F80B4213EB5C014C0681D93A2EBB927C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	8.28662460373652721	48	46	47	t	01020000A034BF0D000A00000080B4213EB5C014C0681D93A2EBB927C09A9999999999E93F6025AB707C7704C0681D93A2EBB927C09A9999999999E93F80BB3BE9B35904C0F042B78079B227C09A9999999999E93FC04AFEDEDCB503C0F042B78079B227C09A9999999999E93F00516A098377F9BF70FA24AAF2F325C09A9999999999E93F00E041007F77BDBFF035E889C6EF25C09A9999999999E93F00DF4C185D17E53F40E462BA616324C09A9999999999E93F00DF4C185D17E53F680249B66DA721C09A9999999999E93F000FDD6C5825E93F68FFFF008E6621C09A9999999999E93F000FDD6C5825E93F28897F828FFD20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	1.42077893475734118	49	48	49	t	01020000A034BF0D00040000000010C12DEE49CFBF28897F828FFD20C09A9999999999E93F0023C0181341E6BF28897F828FFD20C09A9999999999E93F402BE47CB0A0F0BF28897F828FFD20C09A9999999999E93F40BDD35CC1B5F7BFE8968166ED1A20C09A9999999999E93F	\N	\N
first_floor	\N	0.250669824930980667	50	50	48	t	01020000A034BF0D00020000000000A10A9780793F28897F828FFD20C09A9999999999E93F0010C12DEE49CFBF28897F828FFD20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.77958261739550494	51	47	50	t	01020000A034BF0D0003000000000FDD6C5825E93F28897F828FFD20C09A9999999999E93F0043CA763143DD3F28897F828FFD20C09A9999999999E93F0000A10A9780793F28897F828FFD20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	1.64072386883400156	52	49	51	t	01020000A034BF0D000200000040BDD35CC1B5F7BFE8968166ED1A20C09A9999999999E93F80235D8414FB08C0E8968166ED1A20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	0.833029560556820092	53	49	52	t	01020000A034BF0D000300000040BDD35CC1B5F7BFE8968166ED1A20C09A9999999999E93F80F5B51E2CD5F0BFF0BB7B7DB57D1EC09A9999999999E93F80F5B51E2CD5F0BFE088E89125971DC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	0.4276658036609291	55	53	54	t	01020000A034BF0D000200000000172739EF64F5BF4034A69E5BEE16C09A9999999999E93FC08C2C52A73CFCBF4034A69E5BEE16C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	1.04999999600188687	56	54	55	t	01020000A034BF0D0003000000C08C2C52A73CFCBF4034A69E5BEE16C09A9999999999E93FC0CA04DC865102C04034A69E5BEE16C09A9999999999E93F004DF30EBA8406C04034A69E5BEE16C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048k2	0.954043667811909302	57	56	57	t	01020000A034BF0D00050000008060E6C8A14C0FC0208876BC630013C09A9999999999E93F8060E6C8A14C0FC060BFFFFDC36511C09A9999999999E93F8060E6C8A14C0FC0803FF478093611C09A9999999999E93F40A9C743B6FA0EC0E0E364B6130D11C09A9999999999E93F40A9C743B6FA0EC080A98C83D4800EC09A9999999999E93F	\N	\N
first_floor	\N	0.0899999999999323563	58	58	56	t	01020000A034BF0D00020000008060E6C8A14C0FC0301739B28C5C13C09A9999999999E93F8060E6C8A14C0FC0208876BC630013C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	1.72945421111938025	59	55	58	t	01020000A034BF0D0006000000004DF30EBA8406C04034A69E5BEE16C09A9999999999E93F40D2E141EDB70AC04034A69E5BEE16C09A9999999999E93FE0B61077B8BD0BC04034A69E5BEE16C09A9999999999E93F8060E6C8A14C0FC0705FBBF5E62615C09A9999999999E93F8060E6C8A14C0FC0F0DFAF702CF714C09A9999999999E93F8060E6C8A14C0FC0301739B28C5C13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048k1	0.945085081031279639	60	59	60	t	01020000A034BF0D0005000000004DF30EBA8406C0208876BC630013C09A9999999999E93F004DF30EBA8406C060BFFFFDC36511C09A9999999999E93F004DF30EBA8406C0008FE09DDE1411C09A9999999999E93F804EF30EBA8406C0408EE09DDE1411C09A9999999999E93F804EF30EBA8406C0C05495B43E710EC09A9999999999E93F	\N	\N
first_floor	\N	0.0899999999999323563	61	61	59	t	01020000A034BF0D0002000000004DF30EBA8406C0301739B28C5C13C09A9999999999E93F004DF30EBA8406C0208876BC630013C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	0.892390913162003585	62	55	61	t	01020000A034BF0D0003000000004DF30EBA8406C04034A69E5BEE16C09A9999999999E93F004DF30EBA8406C0F0DFAF702CF714C09A9999999999E93F004DF30EBA8406C0301739B28C5C13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048k4	0.94508508103123845	63	62	63	t	01020000A034BF0D0005000000C08C2C52A73CFCBF208876BC630013C09A9999999999E93FC08C2C52A73CFCBF60BFFFFDC36511C09A9999999999E93FC08C2C52A73CFCBF908EE09DDE1411C09A9999999999E93F008E2C52A73CFCBF408EE09DDE1411C09A9999999999E93F008E2C52A73CFCBFC05495B43E710EC09A9999999999E93F	\N	\N
first_floor	\N	0.0899999999999323563	64	64	62	t	01020000A034BF0D0002000000C08C2C52A73CFCBF301739B28C5C13C09A9999999999E93FC08C2C52A73CFCBF208876BC630013C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	0.892390913162003585	65	54	64	t	01020000A034BF0D0003000000C08C2C52A73CFCBF4034A69E5BEE16C09A9999999999E93FC08C2C52A73CFCBFF0DFAF702CF714C09A9999999999E93FC08C2C52A73CFCBF301739B28C5C13C09A9999999999E93F	\N	\N
first_floor	\N	0.0429537524212110847	66	65	66	t	01020000A034BF0D000300000000B15DBEEEBAE8BF301739B28C5C13C09A9999999999E93F00B15DBEEEBAE8BF604FF6650A5913C09A9999999999E93F0092B9B7F7D5E7BF80CB21856B3C13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	1.12614127079994719	67	53	65	t	01020000A034BF0D000600000000172739EF64F5BF4034A69E5BEE16C09A9999999999E93F00864FEC40D6F3BF1050700BB08A16C09A9999999999E93F808E2A5D2E73E9BF60C0019C85C314C09A9999999999E93F808E2A5D2E73E9BFD0E0F8B5A13214C09A9999999999E93F00B15DBEEEBAE8BF20451FC2991B14C09A9999999999E93F00B15DBEEEBAE8BF301739B28C5C13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kR	0.961965972508309508	68	67	68	t	01020000A034BF0D00050000000092B9B7F7D5E7BF208876BC630013C09A9999999999E93F0092B9B7F7D5E7BF60BFFFFDC36511C09A9999999999E93F0092B9B7F7D5E7BFE01F3BF3A63311C09A9999999999E93F007834CCA51DE7BFA07CCAB59C1C11C09A9999999999E93F007834CCA51DE7BF0078C184C2610EC09A9999999999E93F	\N	\N
first_floor	\N	0.0586234430819274621	69	66	67	t	01020000A034BF0D00020000000092B9B7F7D5E7BF80CB21856B3C13C09A9999999999E93F0092B9B7F7D5E7BF208876BC630013C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	0.355302154765635703	70	69	70	t	01020000A034BF0D00030000008034FF4EEED4E6BF301739B28C5C13C09A9999999999E93F00408109F4EAE0BFB0D5E8FACB1914C09A9999999999E93F002DA4B8CFD2DBBFB0D5E8FACB1914C09A9999999999E93F	\N	\N
first_floor	\N	0.0443731523340138781	71	66	69	t	01020000A034BF0D00020000000092B9B7F7D5E7BF80CB21856B3C13C09A9999999999E93F8034FF4EEED4E6BF301739B28C5C13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	0.512835680985825326	72	52	71	t	01020000A034BF0D000200000080F5B51E2CD5F0BFE088E89125971DC09A9999999999E93F8003FADFAE0FE6BFF04B3A66D0231CC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.674423778852499822	73	47	72	t	01020000A034BF0D0002000000000FDD6C5825E93F28897F828FFD20C09A9999999999E93F000FDD6C5825E93F80CE57DF82481FC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048ky	3.92624478699333057	74	73	74	t	01020000A034BF0D000500000080B4213EB5C014C0409C1657F7752CC09A9999999999E93F80B4213EB5C014C028C3475FA3922DC09A9999999999E93F80B4213EB5C014C050CE498A2AA92DC09A9999999999E93F400781AB8F8B19C0D8BB7CE04B0730C09A9999999999E93F400781AB8F8B19C0FC189D930EA931C09A9999999999E93F	\N	\N
first_floor	\N	0.0453800465674589759	75	75	73	t	01020000A034BF0D000200000080B4213EB5C014C060D06649BB5E2CC09A9999999999E93F80B4213EB5C014C0409C1657F7752CC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.32189675649850358	76	46	75	t	01020000A034BF0D000300000080B4213EB5C014C0681D93A2EBB927C09A9999999999E93F80B4213EB5C014C078A935410F422BC09A9999999999E93F80B4213EB5C014C060D06649BB5E2CC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048ky	1.92035734862469099	77	74	76	t	01020000A034BF0D0002000000400781AB8F8B19C0FC189D930EA931C09A9999999999E93F400781AB8F8B19C0EC12A61DAB9433C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048ky	1.72678156895655377	78	76	77	t	01020000A034BF0D0002000000400781AB8F8B19C0EC12A61DAB9433C09A9999999999E93F400781AB8F8B19C0F0130479B94E35C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048ks	3.29808014868064747	79	78	79	t	01020000A034BF0D0009000000404EBBD74E5A11C060E0DABC1EB735C09A9999999999E93F000B89325E7F0FC060E0DABC1EB735C09A9999999999E93F2022620156D30EC060E0DABC1EB735C09A9999999999E93FC0379EEF77860AC0AC5D137FBA4036C09A9999999999E93FE0398EFBAF8608C0AC5D137FBA4036C09A9999999999E93F0010EE36EA6208C0EC62A737334536C09A9999999999E93FC0D782B56DC6F8BFEC62A737334536C09A9999999999E93FC01D7E3B0B74F8BF501707100D4036C09A9999999999E93F001E7E3B0B74F4BF501707100D4036C09A9999999999E93F	\N	\N
first_floor	\N	0.250000000000483169	80	80	78	t	01020000A034BF0D00020000006050BBD74E5A12C060E0DABC1EB735C09A9999999999E93F404EBBD74E5A11C060E0DABC1EB735C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048ky	1.96701315350947659	81	77	80	t	01020000A034BF0D0004000000400781AB8F8B19C0F0130479B94E35C09A9999999999E93F80D5259CFAE917C060E0DABC1EB735C09A9999999999E93F20193296EEF413C060E0DABC1EB735C09A9999999999E93F6050BBD74E5A12C060E0DABC1EB735C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048k8	1.27613336202121364	82	81	82	t	01020000A034BF0D0004000000F05DA33F68DE20C09CD0749DE5AC35C09A9999999999E93F48C2DE1EB8AB21C09CD0749DE5AC35C09A9999999999E93F20243411B0CE21C09CD0749DE5AC35C09A9999999999E93F308A991BCBF222C0A483A722F33E36C09A9999999999E93F	\N	\N
first_floor	\N	0.249999999999488409	83	83	81	t	01020000A034BF0D0002000000105FA33F685E20C09CD0749DE5AC35C09A9999999999E93FF05DA33F68DE20C09CD0749DE5AC35C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048ky	1.95047189837529489	84	77	83	t	01020000A034BF0D0004000000400781AB8F8B19C0F0130479B94E35C09A9999999999E93FF0F9433D40041BC09CD0749DE5AC35C09A9999999999E93F60F5CFC030221FC09CD0749DE5AC35C09A9999999999E93F105FA33F685E20C09CD0749DE5AC35C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048k8	2.02896715623166379	85	82	84	t	01020000A034BF0D0006000000308A991BCBF222C0A483A722F33E36C09A9999999999E93F28CE986A3C7223C0A483A722F33E36C09A9999999999E93F488ADD50167623C0ACE1C915E04036C09A9999999999E93FF097B627E37826C0ACE1C915E04036C09A9999999999E93FF8CABD00F07D26C0244846A9593E36C09A9999999999E93FF8CABD00F0FD26C0244846A9593E36C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048k8	1.21357020913911451	86	82	85	t	01020000A034BF0D0002000000308A991BCBF222C0A483A722F33E36C09A9999999999E93F78B7711D6F3B21C0FC6CBB21A11A37C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kr	3.52797968789575611	87	86	87	t	01020000A034BF0D0007000000F05DA33F68DE20C0EC12A61DAB9433C09A9999999999E93F50C2DE1EB8AB21C0EC12A61DAB9433C09A9999999999E93FF8B832025EC721C0EC12A61DAB9433C09A9999999999E93F9051437018B822C0385FAE54080D34C09A9999999999E93FE08CC814B4EA26C0385FAE54080D34C09A9999999999E93F18418B45642427C054B90F6DE02934C09A9999999999E93FD84014EA1F7127C054B90F6DE02934C09A9999999999E93F	\N	\N
first_floor	\N	0.249999999999488409	88	88	86	t	01020000A034BF0D0002000000105FA33F685E20C0EC12A61DAB9433C09A9999999999E93FF05DA33F68DE20C0EC12A61DAB9433C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048ky	1.79809885877850206	89	76	88	t	01020000A034BF0D0003000000400781AB8F8B19C0EC12A61DAB9433C09A9999999999E93F60F5CFC030221FC0EC12A61DAB9433C09A9999999999E93F105FA33F685E20C0EC12A61DAB9433C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kp	2.52805892473377458	90	89	90	t	01020000A034BF0D0004000000404EBBD74E5A11C0FC189D930EA931C09A9999999999E93FC000B28EED410EC0FC189D930EA931C09A9999999999E93F80FA057293DD0DC0FC189D930EA931C09A9999999999E93F40C6E66CB0FC02C084FF40F42A0533C09A9999999999E93F	\N	\N
first_floor	\N	0.250000000000483169	91	91	89	t	01020000A034BF0D00020000006050BBD74E5A12C0FC189D930EA931C09A9999999999E93F404EBBD74E5A11C0FC189D930EA931C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048ky	1.79809885877850206	92	74	91	t	01020000A034BF0D0003000000400781AB8F8B19C0FC189D930EA931C09A9999999999E93F409E1DE8A69314C0FC189D930EA931C09A9999999999E93F6050BBD74E5A12C0FC189D930EA931C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kp	1.79483799915185571	93	90	92	t	01020000A034BF0D000400000040C6E66CB0FC02C084FF40F42A0533C09A9999999999E93F40C6E66CB0FC02C0B44118D7160933C09A9999999999E93F40B184E4298AF3BF64CF6C460A3034C09A9999999999E93F808B683C3A23F1BF64CF6C460A3034C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kp	1.51190153495346058	94	90	93	t	01020000A034BF0D000300000040C6E66CB0FC02C084FF40F42A0533C09A9999999999E93F80CCB0601C18F5BF8433AFAC16F731C09A9999999999E93F4094A3A68EC6F4BF8433AFAC16F731C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kp	1.37349253673596339	95	93	94	t	01020000A034BF0D00040000004094A3A68EC6F4BF8433AFAC16F731C09A9999999999E93F8039967AA6F3E5BF10AC19F64A5A31C09A9999999999E93F00EA7F2C6B27E1BF10AC19F64A5A31C09A9999999999E93F000E219E8222D2BFFC302EA7991931C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kp	0.692126494316682606	96	93	95	t	01020000A034BF0D00030000004094A3A68EC6F4BF8433AFAC16F731C09A9999999999E93F800ABFD434D6ECBF747473F0CD5C32C09A9999999999E93F802FA1F870ABE8BF747473F0CD5C32C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.985541604671849925	97	35	96	t	01020000A034BF0D0003000000B08896D3608224C0184F4FFC5FAF27C09A9999999999E93F78D5128EF50D25C0E89BCBB6F43A28C09A9999999999E93F78D5128EF50D25C018CFFEE9276E29C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.63552649702931951	98	33	97	t	01020000A034BF0D000500000088D2CCD1059329C080B5B562C69525C09A9999999999E93FD07F018698DF2AC0380881AE334924C09A9999999999E93FD07F018698DF2AC008686E4EFB9E21C09A9999999999E93F10DF512003302BC0C8081EB4904E21C09A9999999999E93F10DF512003302BC010E0328373FB20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.649886544078981387	99	97	98	t	01020000A034BF0D000200000010DF512003302BC010E0328373FB20C09A9999999999E93F10DF512003302BC02008B22A6B5D1FC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	1.58093973909596341	100	99	100	t	01020000A034BF0D0005000000406DC0E3AC1129C010E0328373FB20C09A9999999999E93FE8387EC2D42A28C010E0328373FB20C09A9999999999E93F70F689038ED127C0E08AD0B2B25421C09A9999999999E93F78C44D3B84D127C0E08AD0B2B25421C09A9999999999E93F906BECE3AC9126C0F8316F5BDB1420C09A9999999999E93F	\N	\N
first_floor	\N	0.259251683000996991	101	101	99	t	01020000A034BF0D00020000007045B886699629C010E0328373FB20C09A9999999999E93F406DC0E3AC1129C010E0328373FB20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.800000000000011369	102	97	101	t	01020000A034BF0D000300000010DF512003302BC010E0328373FB20C09A9999999999E93F68438DFF527D2AC010E0328373FB20C09A9999999999E93F7045B886699629C010E0328373FB20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	0.976126239503715909	103	100	102	t	01020000A034BF0D0003000000906BECE3AC9126C0F8316F5BDB1420C09A9999999999E93F686694701B7827C0306E8E9DD95C1EC09A9999999999E93F686694701B7827C0906DDB720E011DC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	1.00397283951121108	104	102	103	t	01020000A034BF0D0003000000686694701B7827C0906DDB720E011DC09A9999999999E93F1084D38C95E327C040325D3A1A2A1CC09A9999999999E93F1084D38C95E328C040325D3A1A2A1AC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	1.63892272053361054	105	102	104	t	01020000A034BF0D0004000000686694701B7827C0906DDB720E011DC09A9999999999E93FE0FCB6D1F14427C0809A2035BB9A1CC09A9999999999E93FE0FCB6D1F14427C0203070B2579A17C09A9999999999E93F28A17C8670EB26C0B078FB1B55E716C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	0.429973598563549331	106	104	105	t	01020000A034BF0D000200000028A17C8670EB26C0B078FB1B55E716C09A9999999999E93F88AE9C064B0F26C0B078FB1B55E716C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	1.04999999600188687	107	105	106	t	01020000A034BF0D000300000088AE9C064B0F26C0B078FB1B55E716C09A9999999999E93F50773460860225C0B078FB1B55E716C09A9999999999E93FE06C256DB1F523C0B078FB1B55E716C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kw	0.944950908845351822	108	107	108	t	01020000A034BF0D0005000000E06C256DB1F523C0F0F826E7590B13C09A9999999999E93FE06C256DB1F523C03030B028BA7011C09A9999999999E93FE06C256DB1F523C0502EEA7BC41F11C09A9999999999E93FC06C256DB1F523C0102EEA7BC41F11C09A9999999999E93FC06C256DB1F523C0606A3F6271870EC09A9999999999E93F	\N	\N
first_floor	\N	0.0899999999996197175	109	109	107	t	01020000A034BF0D0002000000E06C256DB1F523C0A086E9DC826713C09A9999999999E93FE06C256DB1F523C0F0F826E7590B13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	0.874825463743505338	110	106	109	t	01020000A034BF0D0003000000E06C256DB1F523C0B078FB1B55E716C09A9999999999E93FE06C256DB1F523C0604F609B220215C09A9999999999E93FE06C256DB1F523C0A086E9DC826713C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kv	0.953872625850570866	111	110	111	t	01020000A034BF0D000500000088E0DC5CA2C321C0F0F826E7590B13C09A9999999999E93F88E0DC5CA2C321C03030B028BA7011C09A9999999999E93F88E0DC5CA2C321C060F6B3ACE54011C09A9999999999E93F6090243E1DD821C0B09624EAEF1711C09A9999999999E93F6090243E1DD821C02099CA851A970EC09A9999999999E93F	\N	\N
first_floor	\N	0.0899999999996197175	112	112	110	t	01020000A034BF0D000200000088E0DC5CA2C321C0A086E9DC826713C09A9999999999E93F88E0DC5CA2C321C0F0F826E7590B13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	1.72239760869136704	113	106	112	t	01020000A034BF0D0006000000E06C256DB1F523C0B078FB1B55E716C09A9999999999E93F6064167ADCE822C0B078FB1B55E716C09A9999999999E93FF8562C5F519E22C0B078FB1B55E716C09A9999999999E93F88E0DC5CA2C321C0D08B5C17F73115C09A9999999999E93F88E0DC5CA2C321C0604F609B220215C09A9999999999E93F88E0DC5CA2C321C0A086E9DC826713C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kd	0.945075263554304601	114	113	114	t	01020000A034BF0D000500000088AE9C064B0F26C0F0F826E7590B13C09A9999999999E93F88AE9C064B0F26C03030B028BA7011C09A9999999999E93F88AE9C064B0F26C020D03715E51F11C09A9999999999E93FA0AE9C064B0F26C0F0CF3715E51F11C09A9999999999E93FA0AE9C064B0F26C0A026A42F30870EC09A9999999999E93F	\N	\N
first_floor	\N	0.0899999999996197175	115	115	113	t	01020000A034BF0D000200000088AE9C064B0F26C0A086E9DC826713C09A9999999999E93F88AE9C064B0F26C0F0F826E7590B13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	0.874825463743505338	116	105	115	t	01020000A034BF0D000300000088AE9C064B0F26C0B078FB1B55E716C09A9999999999E93F88AE9C064B0F26C0604F609B220215C09A9999999999E93F88AE9C064B0F26C0A086E9DC826713C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kW	0.0226459209316883375	117	116	117	t	01020000A034BF0D0002000000307CAFA8562828C050F726E7590B13C09A9999999999E93F78DEA186893028C0C032422BF4FA12C09A9999999999E93F	\N	\N
first_floor	\N	0.116738465468237254	118	118	116	t	01020000A034BF0D0003000000280AB6A6490728C0A086E9DC826713C09A9999999999E93F280AB6A6490728C070DB19EB734D13C09A9999999999E93F307CAFA8562828C050F726E7590B13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	1.10446169916671755	119	104	118	t	01020000A034BF0D000400000028A17C8670EB26C0B078FB1B55E716C09A9999999999E93F30E804AD0F1C27C0A0EAEACE168616C09A9999999999E93F280AB6A6490728C0B0A688DBA2AF14C09A9999999999E93F280AB6A6490728C0A086E9DC826713C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	0.24801179887113603	120	119	120	t	01020000A034BF0D0003000000688875DFD06628C0A086E9DC826713C09A9999999999E93FA065A92255B228C0104151638BFE13C09A9999999999E93F688C0E9784C628C0104151638BFE13C09A9999999999E93F	\N	\N
first_floor	\N	0.127279220613563282	121	121	119	t	01020000A034BF0D0002000000C0409464BC3828C050F726E7590B13C09A9999999999E93F688875DFD06628C0A086E9DC826713C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kW	0.0226459209316883375	122	117	121	t	01020000A034BF0D000200000078DEA186893028C0C032422BF4FA12C09A9999999999E93FC0409464BC3828C050F726E7590B13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kW	1.04118803574269925	123	117	122	t	01020000A034BF0D000700000078DEA186893028C0C032422BF4FA12C09A9999999999E93F78DEA186893028C0902EB028BA7011C09A9999999999E93F78DEA186893028C000E1E53F5B4811C09A9999999999E93FD0FA5B62912228C0B0195AF76A2C11C09A9999999999E93FD0FA5B62912228C0E02249BDDC8C0EC09A9999999999E93F700AB2397E0228C06061A11A900C0EC09A9999999999E93F700AB2397E0228C0A0D1B7C8D7ED0DC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	1.60013307503500357	124	100	123	t	01020000A034BF0D0002000000906BECE3AC9126C0F8316F5BDB1420C09A9999999999E93FA85F773F685E23C0F8316F5BDB1420C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NP	1.96176447673742715	125	124	125	t	01020000A034BF0D0005000000082570794AC931C068550ABE186B28C09A9999999999E93F082570794AC931C0705AA5281E3A29C09A9999999999E93F0C42CADD85C831C06820F15FA73B29C09A9999999999E93F0C42CADD85C831C060B6EF8E3B8629C09A9999999999E93F5472A2F7BBC930C0D0553F5BCF832BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	126	126	124	t	01020000A034BF0D0002000000082570794AC931C0289D3316882B28C09A9999999999E93F082570794AC931C068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.1657874417945493	127	28	126	t	01020000A034BF0D0003000000082570794AC931C0786CC2FEA5D625C09A9999999999E93F082570794AC931C03876020EDC0E27C09A9999999999E93F082570794AC931C0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.607904212753084039	165	163	164	t	01020000A034BF0D000200000009E94918F3B950C070E8FB28F59F27C09A9999999999E93F0B215CFFDAE050C070E8FB28F59F27C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NP	3.49703926811741361	128	125	127	t	01020000A034BF0D00060000005472A2F7BBC930C0D0553F5BCF832BC09A9999999999E93F5472A2F7BBC930C0483EF09E1A1530C09A9999999999E93FA80C72DCCF9730C0F4A320BA064730C09A9999999999E93FA80C72DCCF9730C0441F5EAA7EFF30C09A9999999999E93F906AF0AF2EA330C02C7DDC7DDD0A31C09A9999999999E93F906AF0AF2EA330C03418283FC22731C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NP	1.35984340497680734	129	125	128	t	01020000A034BF0D00030000005472A2F7BBC930C0D0553F5BCF832BC09A9999999999E93F046FE3542D1A30C0284FC115B2242AC09A9999999999E93F5847053DAA6C2FC0284FC115B2242AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NK	2.0644775232227639	130	129	130	t	01020000A034BF0D0004000000C043F5649C0133C068550ABE186B28C09A9999999999E93FC043F5649C0133C0587C3BC6C48729C09A9999999999E93FC043F5649C0133C0A8C447C8EF8E29C09A9999999999E93F407F0EE7231034C0A83B7ACCFEAB2BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	131	131	129	t	01020000A034BF0D0002000000C043F5649C0133C0289D3316882B28C09A9999999999E93FC043F5649C0133C068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.1657874417945493	132	27	131	t	01020000A034BF0D0003000000C043F5649C0133C0786CC2FEA5D625C09A9999999999E93FC043F5649C0133C03876020EDC0E27C09A9999999999E93FC043F5649C0133C0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NK	3.38755183729869058	133	130	132	t	01020000A034BF0D0006000000407F0EE7231034C0A83B7ACCFEAB2BC09A9999999999E93F407F0EE7231034C034B18D57322930C09A9999999999E93F208CD6DFB02F34C014BE5550BF4830C09A9999999999E93F208CD6DFB02F34C070BE8E41EFFD30C09A9999999999E93FF80FE594552334C0983A808C4A0A31C09A9999999999E93FF80FE594552334C0541C6620062731C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NK	1.3273124510810661	134	130	133	t	01020000A034BF0D0003000000407F0EE7231034C0A83B7ACCFEAB2BC09A9999999999E93F7CF56A42CAD334C0284FC115B2242AC09A9999999999E93F3C0FFB33E41235C0284FC115B2242AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NJ	2.0677973646319483	135	134	135	t	01020000A034BF0D00050000004458A3AC7DFC38C068550ABE186B28C09A9999999999E93F4458A3AC7DFC38C0685AA5281E3A29C09A9999999999E93F4475FD10B9FB38C06820F15FA73B29C09A9999999999E93F4475FD10B9FB38C058B6EF8E3B8629C09A9999999999E93FD818A880BDE937C0286F9AAF32AA2BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	136	136	134	t	01020000A034BF0D00020000004458A3AC7DFC38C0289D3316882B28C09A9999999999E93F4458A3AC7DFC38C068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.16578744179462035	137	14	136	t	01020000A034BF0D00030000004458A3AC7DFC38C0506CC2FEA5D625C09A9999999999E93F4458A3AC7DFC38C03876020EDC0E27C09A9999999999E93F4458A3AC7DFC38C0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NJ	3.40741505543590417	138	135	137	t	01020000A034BF0D0006000000D818A880BDE937C0286F9AAF32AA2BC09A9999999999E93FD818A880BDE937C0F4CA1D494C2830C09A9999999999E93FB82570794AC937C014BE5550BF4830C09A9999999999E93FB82570794AC937C070BE8E41EFFD30C09A9999999999E93F2C4318C888D637C0E4DB36902D0B31C09A9999999999E93F2C4318C888D637C09C894580782A31C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NJ	1.32936878524932167	139	135	138	t	01020000A034BF0D0003000000D818A880BDE937C0286F9AAF32AA2BC09A9999999999E93FDC88BB33FD2637C0284FC115B2242AC09A9999999999E93F9CA24B2517E636C0284FC115B2242AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Ok	2.08872967956472255	140	139	140	t	01020000A034BF0D000500000068B4326F73253AC068550ABE186B28C09A9999999999E93F68B4326F73253AC0605AA5281E3A29C09A9999999999E93F98832AC3562B3AC0C0F894D0E44529C09A9999999999E93F98832AC3562B3AC0F8DD4B1EFE7B29C09A9999999999E93F24DF7C443B433BC01095F020C7AB2BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	141	141	139	t	01020000A034BF0D000200000068B4326F73253AC0289D3316882B28C09A9999999999E93F68B4326F73253AC068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.16578744179463456	142	13	141	t	01020000A034BF0D000300000068B4326F73253AC0486CC2FEA5D625C09A9999999999E93F68B4326F73253AC03876020EDC0E27C09A9999999999E93F68B4326F73253AC0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Ok	3.39432697435573516	143	140	142	t	01020000A034BF0D000600000024DF7C443B433BC01095F020C7AB2BC09A9999999999E93F24DF7C443B433BC0101B605B5CC72FC09A9999999999E93F24DF7C443B633BC04C48EB17350930C09A9999999999E93F24DF7C443B633BC0ACF8943DC1FD30C09A9999999999E93F04F6522C64563BC0CCE1BE55980A31C09A9999999999E93F04F6522C64563BC074355418BA2931C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Ok	1.35340433436699858	144	140	143	t	01020000A034BF0D000300000024DF7C443B433BC01095F020C7AB2BC09A9999999999E93F3003B61ED10A3CC0F84C7E6C9B1C2AC09A9999999999E93FC83B1535084B3CC0F84C7E6C9B1C2AC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.20000000000003437	145	2	144	t	01020000A034BF0D0003000000C4C1243DDC6F3EC0286CC2FEA5D625C09A9999999999E93FDCC1243DDC6F3EC0606CC2FEA5D625C09A9999999999E93FF4F457700FA33FC0286CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.527802277081462989	146	144	145	t	01020000A034BF0D0002000000F4F457700FA33FC0286CC2FEA5D625C09A9999999999E93F566393BE161540C0286CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.24000000000002331	147	145	146	t	01020000A034BF0D0002000000566393BE161540C0286CC2FEA5D625C09A9999999999E93F78E87E10CFB340C0186CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	5.44443284002908001	148	146	147	t	01020000A034BF0D000200000078E87E10CFB340C0186CC2FEA5D625C09A9999999999E93F36815F3DB26C43C0F86BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.452562665769207229	149	147	148	t	01020000A034BF0D000200000036815F3DB26C43C0F86BC2FEA5D625C09A9999999999E93F7CF02BD09FA643C0F86BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.747437334230813155	150	148	149	t	01020000A034BF0D00030000007CF02BD09FA643C0F86BC2FEA5D625C09A9999999999E93FCE1AF9D64B0644C0F86BC2FEA5D625C09A9999999999E93FD21AF9D64B0644C0F06BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.66155232466857683	151	149	150	t	01020000A034BF0D0002000000D21AF9D64B0644C0F06BC2FEA5D625C09A9999999999E93F7EA01896F95A44C0E86BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.73844767533145728	152	150	151	t	01020000A034BF0D00030000007EA01896F95A44C0E86BC2FEA5D625C09A9999999999E93F064E2C0A7F3945C0E06BC2FEA5D625C09A9999999999E93F0A4E2C0A7F3945C0E06BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	3.4004251164103465	153	151	152	t	01020000A034BF0D00020000000A4E2C0A7F3945C0E06BC2FEA5D625C09A9999999999E93F680B822BC0EC46C0C86BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.641127208258211567	154	152	153	t	01020000A034BF0D0003000000680B822BC0EC46C0C86BC2FEA5D625C09A9999999999E93F680B822BC0EC46C0D06BC2FEA5D625C09A9999999999E93F221156A0D03E47C0C86BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.838872791741778201	155	153	154	t	01020000A034BF0D0002000000221156A0D03E47C0C86BC2FEA5D625C09A9999999999E93FA21559CF30AA47C0C06BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.561127208258241694	156	154	155	t	01020000A034BF0D0003000000A21559CF30AA47C0C06BC2FEA5D625C09A9999999999E93FA21559CF30AA47C0C86BC2FEA5D625C09A9999999999E93F564489D303F247C0C06BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	5.35844767533158972	157	155	156	t	01020000A034BF0D0003000000564489D303F247C0C06BC2FEA5D625C09A9999999999E93F82B49270E59F4AC0A06BC2FEA5D625C09A9999999999E93F82B49270E59F4AC0986BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.561552324668440406	158	156	157	t	01020000A034BF0D000200000082B49270E59F4AC0986BC2FEA5D625C09A9999999999E93F4E6DE562C6E74AC0986BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.638447675331562436	159	157	158	t	01020000A034BF0D00030000004E6DE562C6E74AC0986BC2FEA5D625C09A9999999999E93F1A4E2C0A7F394BC0986BC2FEA5D625C09A9999999999E93F1A4E2C0A7F394BC0906BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.741552324668447227	160	158	159	t	01020000A034BF0D00020000001A4E2C0A7F394BC0906BC2FEA5D625C09A9999999999E93FBEAAEF396A984BC0906BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.55844767533160677	161	159	160	t	01020000A034BF0D0003000000BEAAEF396A984BC0906BC2FEA5D625C09A9999999999E93F86B49270E55F4CC0906BC2FEA5D625C09A9999999999E93F86B49270E55F4CC0886BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	3.27782804268160977	162	160	161	t	01020000A034BF0D000300000086B49270E55F4CC0886BC2FEA5D625C09A9999999999E93FC6C7FB3337EC4DC0786BC2FEA5D625C09A9999999999E93FBE963790A6FC4DC0982FD38DE89425C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	6.34239515832765299	163	161	162	t	01020000A034BF0D0006000000BE963790A6FC4DC0982FD38DE89425C09A9999999999E93FAE6A10B7E3FE4DC0982FD38DE89425C09A9999999999E93FAA6AC9444B0B4EC0882FB7C486C625C09A9999999999E93FDA9DFC777EBE4EC0882FB7C486C625C09A9999999999E93F0AD12FABB1314FC058FC8391539327C09A9999999999E93F71E8E793CF7950C058FC8391539327C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.01238658515596436	164	162	163	t	01020000A034BF0D000400000071E8E793CF7950C058FC8391539327C09A9999999999E93FF166068C0C7A50C058F077523B9527C09A9999999999E93F056A79DD9BB850C058F077523B9527C09A9999999999E93F09E94918F3B950C070E8FB28F59F27C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.99433908850542707	166	164	165	t	01020000A034BF0D00020000000B215CFFDAE050C070E8FB28F59F27C09A9999999999E93F05B2C63F7EA051C070E8FB28F59F27C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.966736519075482192	167	165	166	t	01020000A034BF0D000300000005B2C63F7EA051C070E8FB28F59F27C09A9999999999E93F05B2C63F7EA051C0681060D9862828C09A9999999999E93F05B2C63F7EA051C0D076C63FED8E29C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.13122376894452259	168	165	167	t	01020000A034BF0D000200000005B2C63F7EA051C070E8FB28F59F27C09A9999999999E93FCBB62738E4E851C070E8FB28F59F27C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.167620750528982398	169	167	168	t	01020000A034BF0D0002000000CBB62738E4E851C070E8FB28F59F27C09A9999999999E93F95208A849EF351C070E8FB28F59F27C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.44891976623282615	170	168	169	t	01020000A034BF0D000500000095208A849EF351C070E8FB28F59F27C09A9999999999E93F8B3AD6F0025052C018B85C8B18832AC09A9999999999E93F3FA1778B905952C018B85C8B18832AC09A9999999999E93F0D40A11DB16152C088AEA91C1DC42AC09A9999999999E93F0D40A11DB16152C0F8BDA57F49EC2AC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.39214721059835256	171	169	170	t	01020000A034BF0D00020000000D40A11DB16152C0F8BDA57F49EC2AC09A9999999999E93F0D40A11DB16152C098378F0411B52FC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.737706600161004644	173	169	171	t	01020000A034BF0D00030000000D40A11DB16152C0F8BDA57F49EC2AC09A9999999999E93F378A5932526D52C0F8BDA57F49EC2AC09A9999999999E93F15AF5FB3E79052C0F8BDA57F49EC2AC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	4.03144711105501585	174	168	173	t	01020000A034BF0D000500000095208A849EF351C070E8FB28F59F27C09A9999999999E93FE98BC495C05C52C0D88D289FE45624C09A9999999999E93FE98BC495C05C52C0E0988167C6A621C09A9999999999E93F71CFCA12276252C0A07C4F7F927B21C09A9999999999E93F71CFCA12276252C0D8AB83DC21FE20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.655000031109011616	175	173	174	t	01020000A034BF0D000200000071CFCA12276252C0D8AB83DC21FE20C09A9999999999E93F71CFCA12276252C0B05F05658B5D1FC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	1.45346949794322988	176	175	176	t	01020000A034BF0D0004000000755CA765852252C0D8AB83DC21FE20C09A9999999999E93F9937A1E4EFFE51C0D8AB83DC21FE20C09A9999999999E93F61FEC49CB4EE51C0D8AB83DC21FE20C09A9999999999E93F41E5377191D151C0E8E21A80081520C09A9999999999E93F	\N	\N
first_floor	\N	0.244242939585035401	177	177	175	t	01020000A034BF0D000200000071CFCA12273252C0D8AB83DC21FE20C09A9999999999E93F755CA765852252C0D8AB83DC21FE20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.75	178	173	177	t	01020000A034BF0D000300000071CFCA12276252C0D8AB83DC21FE20C09A9999999999E93F4DF4D093BC5552C0D8AB83DC21FE20C09A9999999999E93F71CFCA12273252C0D8AB83DC21FE20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	1.56939305459496836	179	176	178	t	01020000A034BF0D000200000041E5377191D151C0E8E21A80081520C09A9999999999E93FBDE1A681206D51C0E8E21A80081520C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	0.812508065997468498	180	176	179	t	01020000A034BF0D000300000041E5377191D151C0E8E21A80081520C09A9999999999E93F6D1D9B4B54EF51C02043025AE34D1EC09A9999999999E93F6D1D9B4B54EF51C0D088E7334CAF1DC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	0.452317861665538001	181	179	180	t	01020000A034BF0D00020000006D1D9B4B54EF51C0D088E7334CAF1DC09A9999999999E93F1D1F5481CC0352C0E06D57D8C8671CC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	1.82371771601757882	182	179	181	t	01020000A034BF0D00040000006D1D9B4B54EF51C0D088E7334CAF1DC09A9999999999E93F9548DAE5F0E851C0503BDAD715491DC09A9999999999E93F9548DAE5F0E851C0E0B95E18678B17C09A9999999999E93FA18F30A7BFDD51C0B02AC32D53D816C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	0.454891787035023754	183	181	182	t	01020000A034BF0D0002000000A18F30A7BFDD51C0B02AC32D53D816C09A9999999999E93F6D6DBFB4A2C051C0B02AC32D53D816C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	1.04999999600187266	184	182	183	t	01020000A034BF0D00030000006D6DBFB4A2C051C0B02AC32D53D816C09A9999999999E93F2DF9271B099F51C0B02AC32D53D816C09A9999999999E93F398590816F7D51C0B02AC32D53D816C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fO	0.920346444524519858	185	184	185	t	01020000A034BF0D0005000000398590816F7D51C0D06BAE083BFC12C09A9999999999E93F398590816F7D51C010A3374A9B6111C09A9999999999E93F398590816F7D51C0507418EAB51011C09A9999999999E93F118590816F7D51C0D07118EAB51011C09A9999999999E93F118590816F7D51C0A0119B78979B0EC09A9999999999E93F	\N	\N
first_floor	\N	0.0899999999993923439	186	186	184	t	01020000A034BF0D0002000000398590816F7D51C080F870FE635813C09A9999999999E93F398590816F7D51C0D06BAE083BFC12C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	0.874935855285499997	187	183	186	t	01020000A034BF0D0003000000398590816F7D51C0B02AC32D53D816C09A9999999999E93F398590816F7D51C040C1E7BC03F314C09A9999999999E93F398590816F7D51C080F870FE635813C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fV	0.942059195305055441	188	187	188	t	01020000A034BF0D0005000000D33D983A013851C0D06BAE083BFC12C09A9999999999E93FD33D983A013851C010A3374A9B6111C09A9999999999E93FD33D983A013851C0F033A132F03E11C09A9999999999E93F5F33C196903A51C030DB1170FA1511C09A9999999999E93F5F33C196903A51C0E03EA86C0E910EC09A9999999999E93F	\N	\N
first_floor	\N	0.0899999999993923439	189	189	187	t	01020000A034BF0D0002000000D33D983A013851C080F870FE635813C09A9999999999E93FD33D983A013851C0D06BAE083BFC12C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	1.70199870912001217	190	183	189	t	01020000A034BF0D0006000000398590816F7D51C0B02AC32D53D816C09A9999999999E93FF110F9E7D55B51C0B02AC32D53D816C09A9999999999E93FAD8D2C802B5451C0B02AC32D53D816C09A9999999999E93FD33D983A013851C0202D7ED4AE1515C09A9999999999E93FD33D983A013851C040C1E7BC03F314C09A9999999999E93FD33D983A013851C080F870FE635813C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f5	0.920346444524489327	191	190	191	t	01020000A034BF0D00050000006D6DBFB4A2C051C0D06BAE083BFC12C09A9999999999E93F6D6DBFB4A2C051C010A3374A9B6111C09A9999999999E93F6D6DBFB4A2C051C0D07318EAB51011C09A9999999999E93F4F6DBFB4A2C051C0F07118EAB51011C09A9999999999E93F4F6DBFB4A2C051C060119B78979B0EC09A9999999999E93F	\N	\N
first_floor	\N	0.0899999999993923439	192	192	190	t	01020000A034BF0D00020000006D6DBFB4A2C051C080F870FE635813C09A9999999999E93F6D6DBFB4A2C051C0D06BAE083BFC12C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	0.874935855285499997	193	182	192	t	01020000A034BF0D00030000006D6DBFB4A2C051C0B02AC32D53D816C09A9999999999E93F6D6DBFB4A2C051C040C1E7BC03F314C09A9999999999E93F6D6DBFB4A2C051C080F870FE635813C09A9999999999E93F	\N	\N
first_floor	\N	0.0225805231300776586	194	193	194	t	01020000A034BF0D0002000000D34E483C5E0552C080F870FE635813C09A9999999999E93F1D5111D6630652C0E0D3E0610A4813C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	1.13135645983353728	195	181	193	t	01020000A034BF0D0005000000A18F30A7BFDD51C0B02AC32D53D816C09A9999999999E93F6DE1564E3CE251C0000E5EBB889016C09A9999999999E93FABCB273A3C0152C0206A4FFE89A014C09A9999999999E93FABCB273A3C0152C0002B7920849A13C09A9999999999E93FD34E483C5E0552C080F870FE635813C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f6	0.936812411220175556	196	195	196	t	01020000A034BF0D00050000001D5111D6630652C02069AE083BFC12C09A9999999999E93F1D5111D6630652C060A0374A9B6111C09A9999999999E93F1D5111D6630652C06070078DC23911C09A9999999999E93F475BE879D40352C0001378CACC1011C09A9999999999E93F475BE879D40352C060AB1840CD9B0EC09A9999999999E93F	\N	\N
first_floor	\N	0.074033158971985813	197	194	195	t	01020000A034BF0D00020000001D5111D6630652C0E0D3E0610A4813C09A9999999999E93F1D5111D6630652C02069AE083BFC12C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	0.311172288924506435	198	197	198	t	01020000A034BF0D00030000006753DA6F690752C080F870FE635813C09A9999999999E93F8988E9A0BB1352C0904A640F871D14C09A9999999999E93F898BBC2C391652C0904A640F871D14C09A9999999999E93F	\N	\N
first_floor	\N	0.0225805231300776586	199	194	197	t	01020000A034BF0D00020000001D5111D6630652C0E0D3E0610A4813C09A9999999999E93F6753DA6F690752C080F870FE635813C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048hL	5.52122048754753525	200	199	200	t	01020000A034BF0D000600000005215CFFDAE050C0308D033138A42CC09A9999999999E93F01215CFFDAE050C090F13E1088712DC09A9999999999E93F01215CFFDAE050C0F0269DCAD1FD2DC09A9999999999E93F9B9DC8D5A9C550C0204239175BD72EC09A9999999999E93F9B9DC8D5A9C550C08430F191E31033C09A9999999999E93F9B9DC8D5A9C550C0B8C98A2B7DAA33C09A9999999999E93F	\N	\N
first_floor	\N	0.200000000000002842	201	201	199	t	01020000A034BF0D000200000007215CFFDAE050C0C8269DCAD13D2CC09A9999999999E93F05215CFFDAE050C0308D033138A42CC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.30832390874199689	202	164	201	t	01020000A034BF0D00030000000B215CFFDAE050C070E8FB28F59F27C09A9999999999E93F0B215CFFDAE050C068C261EB81702BC09A9999999999E93F07215CFFDAE050C0C8269DCAD13D2CC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048hL	1.45462351424960001	203	200	202	t	01020000A034BF0D00040000009B9DC8D5A9C550C0B8C98A2B7DAA33C09A9999999999E93F9B9DC8D5A9C550C0F0BA417B73B833C09A9999999999E93FA9AE5739A5C550C0B47605ED85B833C09A9999999999E93FC95671C5106C50C0B47605ED85B833C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fC	1.03229707249472558	204	203	204	t	01020000A034BF0D000500000039548F320E1C51C0B8C98A2B7DAA33C09A9999999999E93FDFB4E2DFEE3551C0B8C98A2B7DAA33C09A9999999999E93F659E0911F73551C0D06F26F09DAA33C09A9999999999E93F918F6E829B3F51C0D06F26F09DAA33C09A9999999999E93F8B99DDEA2C5551C0B897E291E30034C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048hL	1.09987563520050458	206	200	205	t	01020000A034BF0D00030000009B9DC8D5A9C550C0B8C98A2B7DAA33C09A9999999999E93F5B2F89B178E850C0B8C98A2B7DAA33C09A9999999999E93F39548F320E0C51C0B8C98A2B7DAA33C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fC	3.27866322730670579	207	204	206	t	01020000A034BF0D00060000008B99DDEA2C5551C0B897E291E30034C09A9999999999E93FE7B196E055D951C0B897E291E30034C09A9999999999E93F51D4E22AB9EB51C0140EB26856B733C09A9999999999E93FAD7CEAD536F051C0140EB26856B733C09A9999999999E93F29C01B1F371052C02400ED43553733C09A9999999999E93FB9893B5B231252C02400ED43553733C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fC	0.908632209018369275	208	204	207	t	01020000A034BF0D00020000008B99DDEA2C5551C0B897E291E30034C09A9999999999E93F39548F320E2C51C000AD1B735EA534C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	6.51757263345607463	209	163	208	t	01020000A034BF0D000300000009E94918F3B950C070E8FB28F59F27C09A9999999999E93FB76D2518584C50C0F8C21F2ACD0C2BC09A9999999999E93FB76D2518584C50C00C73BC8BE09E31C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f9	2.49237082320001235	210	209	210	t	01020000A034BF0D000400000027715965B01550C00C73BC8BE09E31C09A9999999999E93F464497C835E44FC00C73BC8BE09E31C09A9999999999E93FCA1217520DE14FC0807C665C8F9831C09A9999999999E93FFACCDAAFEF344FC0CCE03282BCF032C09A9999999999E93F	\N	\N
first_floor	\N	0.258247074031118018	211	211	209	t	01020000A034BF0D00020000003DC11584372650C00C73BC8BE09E31C09A9999999999E93F27715965B01550C00C73BC8BE09E31C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.59573842554701173	212	208	211	t	01020000A034BF0D0003000000B76D2518584C50C00C73BC8BE09E31C09A9999999999E93F1BE61B05CD4950C00C73BC8BE09E31C09A9999999999E93F3DC11584372650C00C73BC8BE09E31C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f9	0.0299574680590118415	213	210	212	t	01020000A034BF0D0002000000FACCDAAFEF344FC0CCE03282BCF032C09A9999999999E93F7266B89BEF344FC0B00C1CCD67F832C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f9	1.17744322134485313	214	210	213	t	01020000A034BF0D0005000000FACCDAAFEF344FC0CCE03282BCF032C09A9999999999E93FA6FC14340A124FC02440A78AF1AA32C09A9999999999E93F6E47867673084FC02440A78AF1AA32C09A9999999999E93F5A408E7673C84EC0F831B78AF12A32C09A9999999999E93F2ACE8A1230C74EC0F831B78AF12A32C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f9	1.40211739276940683	215	213	214	t	01020000A034BF0D00030000002ACE8A1230C74EC0F831B78AF12A32C09A9999999999E93FE2E73E0B30574EC06C651F7CF14A31C09A9999999999E93FEA7130D51B424EC06C651F7CF14A31C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f9	1.29139648914577454	216	213	215	t	01020000A034BF0D00030000002ACE8A1230C74EC0F831B78AF12A32C09A9999999999E93F6A2EAB61AB534EC0747176ECFA1133C09A9999999999E93F02377E00BD514EC0747176ECFA1133C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.262490821504570704	217	208	216	t	01020000A034BF0D0002000000B76D2518584C50C00C73BC8BE09E31C09A9999999999E93FB76D2518584C50C0CC4FF22413E231C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	3.49451475553934765	218	162	217	t	01020000A034BF0D000300000071E8E793CF7950C058FC8391539327C09A9999999999E93F85DC36B23D9950C0B05B0C9FE29726C09A9999999999E93F85DC36B23D9950C018C2720549FE20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.63335439555776096	219	161	218	t	01020000A034BF0D0005000000BE963790A6FC4DC0982FD38DE89425C09A9999999999E93FEA59A73673AA4DC0503C92271B4C24C09A9999999999E93FEA59A73673AA4DC0D04753E376B021C09A9999999999E93FB626740340974DC0007B8616AA6321C09A9999999999E93FB626740340974DC02084700FA3F820C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	1.46276510858943798	220	219	220	t	01020000A034BF0D0004000000A2A11379631F4EC02084700FA3F820C09A9999999999E93F5AEB1F7B8E664EC02084700FA3F820C09A9999999999E93F724584B66D864EC02084700FA3F820C09A9999999999E93F0A196671F6C14EC0C035E923800A20C09A9999999999E93F	\N	\N
first_floor	\N	0.261588322189993505	221	221	219	t	01020000A034BF0D00020000007A382FBFE7FD4DC02084700FA3F820C09A9999999999E93FA2A11379631F4EC02084700FA3F820C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.801993814794997206	222	218	221	t	01020000A034BF0D0003000000B626740340974DC02084700FA3F820C09A9999999999E93FC2EE22BDBCB64DC02084700FA3F820C09A9999999999E93F7A382FBFE7FD4DC02084700FA3F820C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	1.55894712300903393	223	220	222	t	01020000A034BF0D00020000000A196671F6C14EC0C035E923800A20C09A9999999999E93F3ADBB40582894FC0C035E923800A20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	0.80622524884276614	224	220	223	t	01020000A034BF0D00030000000A196671F6C14EC0C035E923800A20C09A9999999999E93F7E87972A08874EC010DF5D118E3D1EC09A9999999999E93F7E87972A08874EC090AF1EB1B49E1DC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	1.8189075880607759	225	223	224	t	01020000A034BF0D00060000007E87972A08874EC090AF1EB1B49E1DC09A9999999999E93F46341E279A904EC05049E9CC24521DC09A9999999999E93F46341E279A904EC05049E9CC24521CC09A9999999999E93FC6B3B7C033924EC0504D1D0058451CC09A9999999999E93FC6B3B7C033924EC0D0EDF74D105A17C09A9999999999E93F3637CF3EBAA54EC050D23B5DDCBD16C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	0.500186748687241334	226	224	225	t	01020000A034BF0D00020000003637CF3EBAA54EC050D23B5DDCBD16C09A9999999999E93FC2F75E5DC0E54EC050D23B5DDCBD16C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	1.0499999960019295	227	225	226	t	01020000A034BF0D0003000000C2F75E5DC0E54EC050D23B5DDCBD16C09A9999999999E93F22E08D90F3284FC050D23B5DDCBD16C09A9999999999E93F32C8BCC3266C4FC050D23B5DDCBD16C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fH	0.961856137703103187	228	227	228	t	01020000A034BF0D0005000000A281797AB7F54FC040599F9BB6E112C09A9999999999E93FB681797AB7F54FC0809028DD164711C09A9999999999E93FB2FD58403CF74FC0C0B02CAEF03A11C09A9999999999E93F1A9627C298F04FC00074A1BCD40511C09A9999999999E93F1A9627C298F04FC0808FD5649B470EC09A9999999999E93F	\N	\N
first_floor	\N	0.090000000000358682	229	229	227	t	01020000A034BF0D00020000009E81797AB7F54FC030EA6191DF3D13C09A9999999999E93FA281797AB7F54FC040599F9BB6E112C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	1.68596100092192858	230	226	229	t	01020000A034BF0D000600000032C8BCC3266C4FC050D23B5DDCBD16C09A9999999999E93F9AB0EBF659AF4FC050D23B5DDCBD16C09A9999999999E93F9E158C6415BC4FC050D23B5DDCBD16C09A9999999999E93F8E81797AB7F54FC0C072D0ADCBF014C09A9999999999E93F8E81797AB7F54FC0F0B2D84F7FD814C09A9999999999E93F9E81797AB7F54FC030EA6191DF3D13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fK	0.952910487115769422	231	230	231	t	01020000A034BF0D000500000046C8BCC3266C4FC040599F9BB6E112C09A9999999999E93F56C8BCC3266C4FC0809028DD164711C09A9999999999E93F72BBBE1935714FC0C0F7182DA41E11C09A9999999999E93F5EC8BCC3266C4FC0205F097D31F610C09A9999999999E93F5EC8BCC3266C4FC040B905E4E1660EC09A9999999999E93F	\N	\N
first_floor	\N	0.090000000000358682	232	232	230	t	01020000A034BF0D000200000042C8BCC3266C4FC030EA6191DF3D13C09A9999999999E93F46C8BCC3266C4FC040599F9BB6E112C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	0.874987778830501384	233	226	232	t	01020000A034BF0D000300000032C8BCC3266C4FC050D23B5DDCBD16C09A9999999999E93F32C8BCC3266C4FC0F0B2D84F7FD814C09A9999999999E93F42C8BCC3266C4FC030EA6191DF3D13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kh	0.952910487115782523	234	233	234	t	01020000A034BF0D0005000000D6F75E5DC0E54EC040599F9BB6E112C09A9999999999E93FEAF75E5DC0E54EC0809028DD164711C09A9999999999E93FFAEA60B3CEEA4EC010F8182DA41E11C09A9999999999E93FE6F75E5DC0E54EC0605F097D31F610C09A9999999999E93FE6F75E5DC0E54EC0C0B805E4E1660EC09A9999999999E93F	\N	\N
first_floor	\N	0.090000000000358682	235	235	233	t	01020000A034BF0D0002000000D2F75E5DC0E54EC030EA6191DF3D13C09A9999999999E93FD6F75E5DC0E54EC040599F9BB6E112C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	0.874987778830501384	236	225	235	t	01020000A034BF0D0003000000C2F75E5DC0E54EC050D23B5DDCBD16C09A9999999999E93FC2F75E5DC0E54EC0F0B2D84F7FD814C09A9999999999E93FD2F75E5DC0E54EC030EA6191DF3D13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kk	0.952486239310288418	237	236	237	t	01020000A034BF0D0007000000FAF10F4A34644EC040599F9BB6E112C09A9999999999E93FFEF10F4A34644EC070CC836B12CA11C09A9999999999E93FB60F302A8D624EC010BA846CD9BC11C09A9999999999E93FBA0F302A8D624EC0709028DD164711C09A9999999999E93FAA8E9AE601664EC00099D4F9702B11C09A9999999999E93F26C4F309175E4EC0E0449E141AEC10C09A9999999999E93F26C4F309175E4EC0C0EDDBB4107B0EC09A9999999999E93F	\N	\N
first_floor	\N	0.090000000000358682	238	238	236	t	01020000A034BF0D0002000000FAF10F4A34644EC030EA6191DF3D13C09A9999999999E93FFAF10F4A34644EC040599F9BB6E112C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	1.0870239143252507	239	224	238	t	01020000A034BF0D00060000003637CF3EBAA54EC050D23B5DDCBD16C09A9999999999E93FA20F302A8DA24EC0B09542B873A416C09A9999999999E93F6E71A9E3CD654EC020A40D8479BE14C09A9999999999E93F7671A9E3CD654EC040FF09E051C713C09A9999999999E93FF6F10F4A34644EC030033E1385BA13C09A9999999999E93FFAF10F4A34644EC030EA6191DF3D13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	0.438053546813286288	240	223	239	t	01020000A034BF0D00020000007E87972A08874EC090AF1EB1B49E1DC09A9999999999E93F662FF341625F4EC0D0EEFB6B85611CC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.586974378475034086	241	218	240	t	01020000A034BF0D0002000000B626740340974DC02084700FA3F820C09A9999999999E93FB626740340974DC0B078244F36981FC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035107309	276	152	275	t	01020000A034BF0D0003000000680B822BC0EC46C0C86BC2FEA5D625C09A9999999999E93F020E52AFCD3A47C0586182EF6F9E24C09A9999999999E93F020E52AFCD3A47C0683A51E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Na	4.02253255828899547	242	241	242	t	01020000A034BF0D000B000000DAB1C2ECD7114CC0680F4036204A23C09A9999999999E93FDAB1C2ECD7114CC0600AA5CB1A7B22C09A9999999999E93F622A0305F4124CC04828A36AAA7622C09A9999999999E93F622A0305F4124CC090CA108FE43122C09A9999999999E93F1A9F961DF8484CC0A8F7C22CD45921C09A9999999999E93F1A9F961DF8484CC0D891020EFB5920C09A9999999999E93F8E0D45AAD4644CC010B091B611D51FC09A9999999999E93F8E0D45AAD4644CC00015E8FE66611AC09A9999999999E93F8E0D45AAD4644CC090F23E6D3A8718C09A9999999999E93FF2BA11D6325C4CC0B05DA4CB2B4218C09A9999999999E93FF2BA11D6325C4CC0B0790C41C7AC17C09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318057816	243	243	241	t	01020000A034BF0D0002000000DAB1C2ECD7114CC0F03951E7C38123C09A9999999999E93FDAB1C2ECD7114CC0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035123385	244	160	243	t	01020000A034BF0D000300000086B49270E55F4CC0886BC2FEA5D625C09A9999999999E93FDAB1C2ECD7114CC0E06082EF6F9E24C09A9999999999E93FDAB1C2ECD7114CC0F03951E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Ot	1.88010631947096618	245	244	245	t	01020000A034BF0D0004000000BEAAEF396A984BC068550ABE186B28C09A9999999999E93FBEAAEF396A984BC0587C3BC6C48729C09A9999999999E93FBEAAEF396A984BC018540ABE18EB29C09A9999999999E93F2E4C9853B3FE4BC0D8D9AC243D842BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	246	246	244	t	01020000A034BF0D0002000000BEAAEF396A984BC0289D3316882B28C09A9999999999E93FBEAAEF396A984BC068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.16578744179496141	247	159	246	t	01020000A034BF0D0003000000BEAAEF396A984BC0906BC2FEA5D625C09A9999999999E93FBEAAEF396A984BC03876020EDC0E27C09A9999999999E93FBEAAEF396A984BC0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Ot	3.49931646816763697	248	245	247	t	01020000A034BF0D00060000002E4C9853B3FE4BC0D8D9AC243D842BC09A9999999999E93F2E4C9853B3FE4BC0888E8D2D1C1830C09A9999999999E93FC2C2D46CCA154CC0B07B06604A4630C09A9999999999E93FC2C2D46CCA154CC0A4F9EEBEFC0331C09A9999999999E93F121A1B61E1114CC0044B62D6CE0B31C09A9999999999E93F121A1B61E1114CC024F45A91932B31C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Ot	1.26935150122306029	249	245	248	t	01020000A034BF0D00030000002E4C9853B3FE4BC0D8D9AC243D842BC09A9999999999E93F4A8BD96CE3554CC068DDA7BF7C272AC09A9999999999E93F8A372226107D4CC068DDA7BF7C272AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NZ	3.96327309345203904	250	249	250	t	01020000A034BF0D0005000000724B5C8671EB4AC0D80E4036204A23C09A9999999999E93F724B5C8671EB4AC0E8E70E2E742D22C09A9999999999E93F724B5C8671EB4AC01846006D942B22C09A9999999999E93FD6723B71F3314BC088A883C18C1121C09A9999999999E93FD6723B71F3314BC03039B25380A317C09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318370455	251	251	249	t	01020000A034BF0D0002000000724B5C8671EB4AC0103A51E7C38123C09A9999999999E93F724B5C8671EB4AC0D80E4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035117967	252	158	251	t	01020000A034BF0D00030000001A4E2C0A7F394BC0906BC2FEA5D625C09A9999999999E93F724B5C8671EB4AC0F86082EF6F9E24C09A9999999999E93F724B5C8671EB4AC0103A51E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Ox	2.07979133821970974	253	252	253	t	01020000A034BF0D00050000004E6DE562C6E74AC068550ABE186B28C09A9999999999E93F4E6DE562C6E74AC0585AA5281E3A29C09A9999999999E93FEE00FE661CE64AC0D80B4318C64029C09A9999999999E93FEE00FE661CE64AC0D8CA9DD61C8129C09A9999999999E93F7AE91EFC805B4AC0A8281A828AAB2BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	254	254	252	t	01020000A034BF0D00020000004E6DE562C6E74AC0289D3316882B28C09A9999999999E93F4E6DE562C6E74AC068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.1657874417949472	255	157	254	t	01020000A034BF0D00030000004E6DE562C6E74AC0986BC2FEA5D625C09A9999999999E93F4E6DE562C6E74AC03876020EDC0E27C09A9999999999E93F4E6DE562C6E74AC0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Ox	3.40476930291122271	256	253	255	t	01020000A034BF0D00060000007AE91EFC805B4AC0A8281A828AAB2BC09A9999999999E93F7AE91EFC805B4AC0E4229913972B30C09A9999999999E93F4ADE226D9D4B4AC0443991315E4B30C09A9999999999E93F4ADE226D9D4B4AC08CB556F793FE30C09A9999999999E93F0AC43961E1514AC00C8184DF1B0B31C09A9999999999E93F0AC43961E1514AC0A49DDFC7092B31C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Ox	1.32059365593731703	257	253	256	t	01020000A034BF0D00030000007AE91EFC805B4AC0A8281A828AAB2BC09A9999999999E93FEA91579972FA49C060CAFCF650272AC09A9999999999E93F8A7B5F7BABDA49C060CAFCF650272AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6N_	4.00734795006558109	258	257	258	t	01020000A034BF0D000A000000DAB1C2ECD7514AC0680F4036204A23C09A9999999999E93FDAB1C2ECD7514AC0680AA5CB1A7B22C09A9999999999E93F52FAFA58D7504AC0402C867C187722C09A9999999999E93F52FAFA58D7504AC0A0C62D7D763122C09A9999999999E93FDE2C15063A114AC0D8909631013321C09A9999999999E93FDE2C15063A114AC0B8264992D03220C09A9999999999E93FDE2C15063A014AC0704D9224A1E51FC09A9999999999E93FDE2C15063A014AC0501ADAB65A7518C09A9999999999E93FE2709892A7074AC030FABF52EE4118C09A9999999999E93FE2709892A7074AC07048720F2BAD17C09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318128871	259	259	257	t	01020000A034BF0D0002000000DAB1C2ECD7514AC0183A51E7C38123C09A9999999999E93FDAB1C2ECD7514AC0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035117967	260	156	259	t	01020000A034BF0D000300000082B49270E59F4AC0986BC2FEA5D625C09A9999999999E93FDAB1C2ECD7514AC0006182EF6F9E24C09A9999999999E93FDAB1C2ECD7514AC0183A51E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Oy	2.02763073589263421	261	260	261	t	01020000A034BF0D0004000000564489D303F247C068550ABE186B28C09A9999999999E93F564489D303F247C0587C3BC6C48729C09A9999999999E93F564489D303F247C0D820D78AE5B729C09A9999999999E93FAE1C522FB46E48C03882FAF9A6AA2BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	262	262	260	t	01020000A034BF0D0002000000564489D303F247C0289D3316882B28C09A9999999999E93F564489D303F247C068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.16578744179487614	263	155	262	t	01020000A034BF0D0003000000564489D303F247C0C06BC2FEA5D625C09A9999999999E93F564489D303F247C03876020EDC0E27C09A9999999999E93F564489D303F247C0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Oy	3.41019758974730847	264	261	263	t	01020000A034BF0D0006000000AE1C522FB46E48C03882FAF9A6AA2BC09A9999999999E93FAE1C522FB46E48C0AC4F894F252B30C09A9999999999E93F7A1156A0D07E48C0443991315E4B30C09A9999999999E93F7A1156A0D07E48C08CB556F793FE30C09A9999999999E93F6E2AA0C7477848C0A483C2A8A50B31C09A9999999999E93F6E2AA0C7477848C03CA01D91932B31C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Oy	1.32161053981249799	265	261	264	t	01020000A034BF0D0003000000AE1C522FB46E48C03882FAF9A6AA2BC09A9999999999E93FA28A11B089CF48C060CAFCF650272AC09A9999999999E93F3A741992C2EF48C060CAFCF650272AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Nz	3.57187488082289617	266	265	266	t	01020000A034BF0D00090000003E1829533EF847C0680F4036204A23C09A9999999999E93F3E1829533EF847C078E80E2E742D22C09A9999999999E93F3E1829533EF847C058F4F36A69E421C09A9999999999E93FF2083A0CBB6E48C08831B086760A20C09A9999999999E93FF2083A0CBB6E48C0D08EC5CE8B141EC09A9999999999E93FF2083A0CBB7E48C0D08EC5CE8B941DC09A9999999999E93FF2083A0CBB7E48C0F0D8A60C70C61AC09A9999999999E93F2A80F0CB5B7848C0B0925A0A76931AC09A9999999999E93F2A80F0CB5B7848C0B070F6186B1D1AC09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318242558	267	267	265	t	01020000A034BF0D00020000003E1829533EF847C0583A51E7C38123C09A9999999999E93F3E1829533EF847C0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035108907	268	154	267	t	01020000A034BF0D0003000000A21559CF30AA47C0C06BC2FEA5D625C09A9999999999E93F3E1829533EF847C0406182EF6F9E24C09A9999999999E93F3E1829533EF847C0583A51E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6OX	2.03012271375862774	269	268	269	t	01020000A034BF0D0004000000221156A0D03E47C068550ABE186B28C09A9999999999E93F221156A0D03E47C0587C3BC6C48729C09A9999999999E93F221156A0D03E47C08823D78AE5B729C09A9999999999E93F12360887E6C146C0C88F0EF08DAB2BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	270	270	268	t	01020000A034BF0D0002000000221156A0D03E47C0289D3316882B28C09A9999999999E93F221156A0D03E47C068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.16578744179486193	271	153	270	t	01020000A034BF0D0003000000221156A0D03E47C0C86BC2FEA5D625C09A9999999999E93F221156A0D03E47C03876020EDC0E27C09A9999999999E93F221156A0D03E47C0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6OX	3.40547304062686207	272	269	271	t	01020000A034BF0D000600000012360887E6C146C0C88F0EF08DAB2BC09A9999999999E93F12360887E6C146C014F38D0B732B30C09A9999999999E93F12360887E6B146C014F38D0B734B30C09A9999999999E93F12360887E6B146C0AC0EE53030FE30C09A9999999999E93F7A9ABDC747B846C07CD74FB2F20A31C09A9999999999E93F7A9ABDC747B846C0C47D1AC8092B31C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6OX	1.32098559466730214	273	269	272	t	01020000A034BF0D000300000012360887E6C146C0C88F0EF08DAB2BC09A9999999999E93FDE6B02D9CD6046C00067F7372B272AC09A9999999999E93F12890472084146C00067F7372B272AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Nu	3.57627822230684078	274	273	274	t	01020000A034BF0D0009000000020E52AFCD3A47C0680F4036204A23C09A9999999999E93F020E52AFCD3A47C078E80E2E742D22C09A9999999999E93F020E52AFCD3A47C0C83463A547ED21C09A9999999999E93F5A22F063EDC146C02886DB77C60920C09A9999999999E93F5A22F063EDC146C050115EFB86121EC09A9999999999E93F62630EBF55B246C0901950D4C9951DC09A9999999999E93F62630EBF55B246C01005A09BE8C31AC09A9999999999E93F36F00DCC5BB846C0909EA333B8931AC09A9999999999E93F36F00DCC5BB846C0D09EFDF7511E1AC09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318270979	275	275	273	t	01020000A034BF0D0002000000020E52AFCD3A47C0683A51E7C38123C09A9999999999E93F020E52AFCD3A47C0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Nt	4.67670373019338914	277	276	277	t	01020000A034BF0D000B000000724B5C8671EB44C0680F4036204A23C09A9999999999E93F724B5C8671EB44C078E80E2E742D22C09A9999999999E93F724B5C8671EB44C07079DFBC210322C09A9999999999E93F982CC7075E1F45C0D8F433B76F3321C09A9999999999E93F982CC7075E1F45C0587707BDEC3220C09A9999999999E93FA26DE562C62F45C060E61CA196E21FC09A9999999999E93FA26DE562C62F45C05038D3CE1B7718C09A9999999999E93FA82D18A3FF2845C0803869D0E54018C09A9999999999E93FA82D18A3FF2845C0D038C3947FCB17C09A9999999999E93F8E522D8DDA6A45C0A0111A44A8BC15C09A9999999999E93F8E522D8DDA6A45C0B0E176D36AB215C09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318370455	278	278	276	t	01020000A034BF0D0002000000724B5C8671EB44C0A03A51E7C38123C09A9999999999E93F724B5C8671EB44C0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.4183696703510229	279	151	278	t	01020000A034BF0D00030000000A4E2C0A7F3945C0E06BC2FEA5D625C09A9999999999E93F724B5C8671EB44C0906182EF6F9E24C09A9999999999E93F724B5C8671EB44C0A03A51E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6OY	2.01930946162143421	280	279	280	t	01020000A034BF0D00040000007EA01896F95A44C068550ABE186B28C09A9999999999E93F7EA01896F95A44C0587C3BC6C48729C09A9999999999E93F7EA01896F95A44C0E0F77AFB22C229C09A9999999999E93F46693BBA19D544C0001B068CA3AA2BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	281	281	279	t	01020000A034BF0D00020000007EA01896F95A44C0289D3316882B28C09A9999999999E93F7EA01896F95A44C068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.16578744179480509	282	150	281	t	01020000A034BF0D00030000007EA01896F95A44C0E86BC2FEA5D625C09A9999999999E93F7EA01896F95A44C03876020EDC0E27C09A9999999999E93F7EA01896F95A44C0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6OY	3.40949385203173794	283	280	282	t	01020000A034BF0D000600000046693BBA19D544C0001B068CA3AA2BC09A9999999999E93F46693BBA19D544C0B0B889D9FD2A30C09A9999999999E93F46693BBA19E544C0B0B889D9FD4A30C09A9999999999E93F46693BBA19E544C01049E962A5FE30C09A9999999999E93FE200242EAEDE44C0D819187B7C0B31C09A9999999999E93FE200242EAEDE44C020C0E290932B31C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6OY	1.32203313285104018	284	280	283	t	01020000A034BF0D000300000046693BBA19D544C0001B068CA3AA2BC09A9999999999E93F46163FCFF73545C00067F7372B272AC09A9999999999E93F7A334168325645C00067F7372B272AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6No	4.66865458146079426	285	284	285	t	01020000A034BF0D00070000003E1829533EB843C0680F4036204A23C09A9999999999E93F3E1829533EB843C078E80E2E742D22C09A9999999999E93F3E1829533EB843C030C3CA70172C22C09A9999999999E93F2C8F819ED0FE43C078E76843CE1121C09A9999999999E93F2C8F819ED0FE43C000E3225AD4C617C09A9999999999E93FD07375614F4144C0E0BD8342DEB215C09A9999999999E93FD07375614F4144C0F025328ABFAD15C09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318427299	286	286	284	t	01020000A034BF0D00020000003E1829533EB843C0C03A51E7C38123C09A9999999999E93F3E1829533EB843C0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035098693	287	149	286	t	01020000A034BF0D0003000000D21AF9D64B0644C0F06BC2FEA5D625C09A9999999999E93F3E1829533EB843C0B86182EF6F9E24C09A9999999999E93F3E1829533EB843C0C03A51E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Od	2.03411578109559965	288	287	288	t	01020000A034BF0D00040000007CF02BD09FA643C068550ABE186B28C09A9999999999E93F7CF02BD09FA643C0507C3BC6C48729C09A9999999999E93F7CF02BD09FA643C0C83F196542B229C09A9999999999E93FDE9E06145A2843C04086AE5559AB2BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	289	289	287	t	01020000A034BF0D00020000007CF02BD09FA643C0289D3316882B28C09A9999999999E93F7CF02BD09FA643C068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.16578744179477667	290	148	289	t	01020000A034BF0D00030000007CF02BD09FA643C0F86BC2FEA5D625C09A9999999999E93F7CF02BD09FA643C04076020EDC0E27C09A9999999999E93F7CF02BD09FA643C0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Od	3.40562176466340372	291	288	290	t	01020000A034BF0D0006000000DE9E06145A2843C04086AE5559AB2BC09A9999999999E93FDE9E06145A2843C0E833F8902F2B30C09A9999999999E93FDE9E06145A1843C0E833F8902F4B30C09A9999999999E93FDE9E06145A1843C0C089A55021FE30C09A9999999999E93F225BD42DAC1E43C048024184C50A31C09A9999999999E93F225BD42DAC1E43C040327BC7052B31C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Od	1.32166497457931276	292	288	291	t	01020000A034BF0D0003000000DE9E06145A2843C04086AE5559AB2BC09A9999999999E93F74683F4144C742C098AC910A02272AC09A9999999999E93FE080118D64A742C098AC910A02272AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Nn	3.97161348987304708	293	292	293	t	01020000A034BF0D000A000000A67E8FB9A41E43C0680F4036204A23C09A9999999999E93FA67E8FB9A41E43C0780AA5CB1A7B22C09A9999999999E93FA6164186B41D43C0786A6BFE597722C09A9999999999E93FA6164186B41D43C0788848FB343122C09A9999999999E93F769FFB5716DE42C0B0AB3242BC3221C09A9999999999E93F769FFB5716DE42C07067FBC9ED3120C09A9999999999E93F769FFB5716CE42C0E0CEF693DBE31FC09A9999999999E93F769FFB5716CE42C0B0A2B1BB977418C09A9999999999E93F001B489B83D442C060C64DA12D4118C09A9999999999E93F001B489B83D442C0407E2B428ED117C09A9999999999E93F	\N	\N
first_floor	\N	0.10867074331845572	294	294	292	t	01020000A034BF0D0002000000A67E8FB9A41E43C0D03A51E7C38123C09A9999999999E93FA67E8FB9A41E43C0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.4183696703509483	295	147	294	t	01020000A034BF0D000300000036815F3DB26C43C0F86BC2FEA5D625C09A9999999999E93FA67E8FB9A41E43C0B86182EF6F9E24C09A9999999999E93FA67E8FB9A41E43C0D03A51E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Oe	2.06553053367635808	296	295	296	t	01020000A034BF0D000400000078E87E10CFB340C068550ABE186B28C09A9999999999E93F78E87E10CFB340C0507C3BC6C48729C09A9999999999E93F78E87E10CFB340C068C547C8EF8E29C09A9999999999E93F2A29A0372B3B41C030C8CC6460AC2BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	297	297	295	t	01020000A034BF0D000200000078E87E10CFB340C0289D3316882B28C09A9999999999E93F78E87E10CFB340C068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.16578744179471983	298	146	297	t	01020000A034BF0D000300000078E87E10CFB340C0186CC2FEA5D625C09A9999999999E93F78E87E10CFB340C04076020EDC0E27C09A9999999999E93F78E87E10CFB340C0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Oe	3.39835996331566248	299	296	298	t	01020000A034BF0D00060000002A29A0372B3B41C030C8CC6460AC2BC09A9999999999E93F2A29A0372B3B41C0E0548718B32B30C09A9999999999E93F2A29A0372B4B41C0E0548718B34B30C09A9999999999E93F2A29A0372B4B41C0C86816C99DFD30C09A9999999999E93FA018A184B04441C0DC89142F930A31C09A9999999999E93FA018A184B04441C048533AC48B2931C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Oe	1.32647447684009023	300	296	299	t	01020000A034BF0D00030000002A29A0372B3B41C030C8CC6460AC2BC09A9999999999E93F10F02ECE829C41C098AC910A02272AC09A9999999999E93F7C08011AA3BC41C098AC910A02272AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Oj	2.05902761104781007	301	300	301	t	01020000A034BF0D0004000000566393BE161540C068550ABE186B28C09A9999999999E93F566393BE161540C0587C3BC6C48729C09A9999999999E93F566393BE161540C0C0C647C8EF8E29C09A9999999999E93FF48BE788A21C3FC0303CC6B005AA2BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	302	302	300	t	01020000A034BF0D0002000000566393BE161540C0289D3316882B28C09A9999999999E93F566393BE161540C068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.1657874417946914	303	145	302	t	01020000A034BF0D0003000000566393BE161540C0286CC2FEA5D625C09A9999999999E93F566393BE161540C03876020EDC0E27C09A9999999999E93F566393BE161540C0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Oj	3.40645825950587167	304	301	303	t	01020000A034BF0D0006000000F48BE788A21C3FC0303CC6B005AA2BC09A9999999999E93FF48BE788A21C3FC044AF70201F2030C09A9999999999E93FF48BE788A2FC3EC044AF70201F4030C09A9999999999E93FF48BE788A2FC3EC01C25AAF5A1FE30C09A9999999999E93F6C3C570A65093FC094D51977640B31C09A9999999999E93F6C3C570A65093FC03C29AF39862A31C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Oj	1.34687394585084452	305	301	304	t	01020000A034BF0D0003000000F48BE788A21C3FC0303CC6B005AA2BC09A9999999999E93F5894C366ED553EC0F84C7E6C9B1C2AC09A9999999999E93FF0CC227D24163EC0F84C7E6C9B1C2AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NC	3.68741054065778773	306	305	306	t	01020000A034BF0D0009000000FEFCFB3B951F40C0680F4036204A23C09A9999999999E93F00FDFB3B951F40C078E80E2E742D22C09A9999999999E93F00FDFB3B951F40C01824F5EA5F2A22C09A9999999999E93FF45DAADB8AF140C0904077D812C51DC09A9999999999E93FF45DAADB8AF140C070D92B503F201CC09A9999999999E93F0A902C7257F740C0C0481A9CDAF11BC09A9999999999E93F86ED2B5F980A41C0C0481A9CDAF11BC09A9999999999E93F862BA340E41141C0D038D4A7392C1CC09A9999999999E93F0ACEA353A31E41C0D038D4A7392C1CC09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318583618	307	307	305	t	01020000A034BF0D0002000000FEFCFB3B951F40C0183B51E7C38123C09A9999999999E93FFEFCFB3B951F40C0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035084127	308	144	307	t	01020000A034BF0D0003000000F4F457700FA33FC0286CC2FEA5D625C09A9999999999E93FFEFCFB3B951F40C0E06182EF6F9E24C09A9999999999E93FFEFCFB3B951F40C0183B51E7C38123C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	3.99249344741750178	309	308	34	t	01020000A034BF0D0002000000609E71E1904427C090039A7CEE912DC09A9999999999E93F609E71E1904427C080B5B562C69525C09A9999999999E93F	\N	\N
first_floor	\N	3.63916967176426942	310	309	308	t	01020000A034BF0D0003000000F87D8A907CF124C05807A30C40F631C09A9999999999E93F609E71E1904427C0600F83CE86F22DC09A9999999999E93F609E71E1904427C090039A7CEE912DC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	3.00850384461020193	311	310	167	t	01020000A034BF0D0002000000CBB62738E4E851C0308D033138A42DC09A9999999999E93FCBB62738E4E851C070E8FB28F59F27C09A9999999999E93F	\N	\N
first_floor	\N	3.50436618393977728	312	311	310	t	01020000A034BF0D000300000089855B35799E51C044E93BEB08DE31C09A9999999999E93FCBB62738E4E851C030E8716F16B02DC09A9999999999E93FCBB62738E4E851C0308D033138A42DC09A9999999999E93F	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lE	1.12003121719965826	313	312	313	t	01020000A034BF0D0002000000B692D5108DFD4DC000245E4E0E412CC00000000000000840D24212692D984DC070E450AF8FAB2AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lE	0.134848155992997931	314	313	314	t	01020000A034BF0D0002000000D24212692D984DC070E450AF8FAB2AC00000000000000840D24212692D984DC0880F09DE84662AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.19507681063849702	315	315	316	t	01020000A034BF0D0003000000E675459C60B34DC090D498BCE34728C00000000000000840E675459C60B34DC0A0AD67B4372B27C00000000000000840E675459C60B34DC0980705A102E425C00000000000000840	\N	\N
second_floor	\N	0.249668621059001339	316	317	315	t	01020000A034BF0D0002000000E675459C60B34DC0E8665D4DB8C728C00000000000000840E675459C60B34DC090D498BCE34728C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lE	0.898174840006691566	317	314	317	t	01020000A034BF0D0004000000D24212692D984DC0880F09DE84662AC00000000000000840E675459C60B34DC038433C11B8F929C00000000000000840E675459C60B34DC0D88D8E5564E429C00000000000000840E675459C60B34DC0E8665D4DB8C728C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.662015579741099258	318	316	318	t	01020000A034BF0D0003000000E675459C60B34DC0980705A102E425C000000000000008409A429D7F36EF4DC0980705A102E425C00000000000000840E2C9D754D2004EC068EA1A4C939D25C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	4.26006738142456953	319	318	319	t	01020000A034BF0D0004000000E2C9D754D2004EC068EA1A4C939D25C00000000000000840321489B53AC94EC068EA1A4C939D25C00000000000000840F609B211CA4B4FC078C1BEBCD0A727C00000000000000840AEC273CF07EC4FC078C1BEBCD0A727C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.9677270889019951	320	319	320	t	01020000A034BF0D0002000000AEC273CF07EC4FC078C1BEBCD0A727C00000000000000840BB735325F37350C078C1BEBCD0A727C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.70822139073615609	321	320	321	t	01020000A034BF0D0003000000BB735325F37350C078C1BEBCD0A727C00000000000000840E110B007F77450C0A8AAA3CFEFAF27C0000000000000084007215CFFDAE050C0A8AAA3CFEFAF27C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lg	1.03229707249457059	322	322	323	t	01020000A034BF0D000500000039548F320E1C51C024CA8A2B7DAA33C00000000000000840DBB4E2DFEE3551C024CA8A2B7DAA33C00000000000000840539E0911F73551C0047026F09DAA33C000000000000008409F8F6E829B3F51C0047026F09DAA33C000000000000008408B99DDEA2C5551C0B897E291E30034C00000000000000840	\N	\N
second_floor	\N	0.25	323	324	322	t	01020000A034BF0D000200000039548F320E0C51C024CA8A2B7DAA33C0000000000000084039548F320E1C51C024CA8A2B7DAA33C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048kN	7.1830583027692958	324	325	324	t	01020000A034BF0D000800000007215CFFDAE050C08842CD9CEABD2CC0000000000000084007215CFFDAE050C07869FEA496DA2DC0000000000000084007215CFFDAE050C018DC663684172EC0000000000000084065ED8AABDE9850C0903C786AB32B30C00000000000000840E7B74B6BDC9850C0AC9BD5B4620533C000000000000008408503F90823C250C024CA8A2B7DAA33C000000000000008405B2F89B178E850C024CA8A2B7DAA33C0000000000000084039548F320E0C51C024CA8A2B7DAA33C00000000000000840	\N	\N
second_floor	\N	0.190521208191000824	325	326	325	t	01020000A034BF0D000200000007215CFFDAE050C0A882E09D5E5C2CC0000000000000084007215CFFDAE050C08842CD9CEABD2CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.3367828797599941	326	321	326	t	01020000A034BF0D000300000007215CFFDAE050C0A8AAA3CFEFAF27C0000000000000084007215CFFDAE050C0B85BAF95B23F2BC0000000000000084007215CFFDAE050C0A882E09D5E5C2CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lg	3.27866322730670579	327	323	327	t	01020000A034BF0D00060000008B99DDEA2C5551C0B897E291E30034C00000000000000840E7B196E055D951C0B897E291E30034C0000000000000084051D4E22AB9EB51C0140EB26856B733C00000000000000840AD7CEAD536F051C0140EB26856B733C0000000000000084029C01B1F371052C02400ED43553733C00000000000000840B9893B5B231252C02400ED43553733C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lg	0.908632209018369275	328	323	328	t	01020000A034BF0D00020000008B99DDEA2C5551C0B897E291E30034C0000000000000084039548F320E2C51C000AD1B735EA534C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.80000000000001137	329	321	329	t	01020000A034BF0D000200000007215CFFDAE050C0A8AAA3CFEFAF27C000000000000008403B548F320E5451C0A8AAA3CFEFAF27C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.889882495248997429	330	329	330	t	01020000A034BF0D00020000003B548F320E5451C0A8AAA3CFEFAF27C0000000000000084061EC4408028D51C0A8AAA3CFEFAF27C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.859309402660437427	331	330	331	t	01020000A034BF0D000300000061EC4408028D51C0A8AAA3CFEFAF27C00000000000000840F14DD1D4FB9F51C028B70634BE4728C00000000000000840F14DD1D4FB9F51C008321BE2052929C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.58714503115441952	332	330	332	t	01020000A034BF0D000300000061EC4408028D51C0A8AAA3CFEFAF27C00000000000000840416759B6498E51C098D3FF5EB2A527C000000000000008409D1B45160EF251C098D3FF5EB2A527C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.44685447965360581	333	332	333	t	01020000A034BF0D00050000009D1B45160EF251C098D3FF5EB2A527C000000000000008406DFF26F3334E52C018F20E46E1862AC0000000000000084079D6CA63715852C018F20E46E1862AC00000000000000840C9129CB2916052C090D498BCE3C72AC00000000000000840C9129CB2916052C090BCA57F49EC2AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.37496728516698852	334	333	334	t	01020000A034BF0D0002000000C9129CB2916052C090BCA57F49EC2AC00000000000000840C9129CB2916052C0F875EB3545AC2FC00000000000000840	\N	\N
second_floor	\N	0.609587404679501788	335	335	336	t	01020000A034BF0D0002000000C9129CB2919052C090BCA57F49EC2AC0000000000000084083DC7F2D95B752C090BCA57F49EC2AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.75	336	333	335	t	01020000A034BF0D0003000000C9129CB2916052C090BCA57F49EC2AC00000000000000840EBED9531FC6C52C090BCA57F49EC2AC00000000000000840C9129CB2919052C090BCA57F49EC2AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	4.05106571891685352	337	332	337	t	01020000A034BF0D00050000009D1B45160EF251C098D3FF5EB2A527C0000000000000084019CCCFD36C5C52C0C04FAA72BC5224C0000000000000084019CCCFD36C5C52C0A8C57491D6A921C000000000000008401DB0D345E36152C088A55501237E21C000000000000008401DB0D345E36152C0C8AB83DC21FE20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.65489527459048702	338	337	338	t	01020000A034BF0D00020000001DB0D345E36152C0C8AB83DC21FE20C000000000000008401DB0D345E36152C060A81CDBA65D1FC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	1.45346949794322655	339	339	340	t	01020000A034BF0D0004000000755CA765852252C0C8AB83DC21FE20C000000000000008409737A1E4EFFE51C0C8AB83DC21FE20C000000000000008405DFEC49CB4EE51C0C8AB83DC21FE20C0000000000000084041E5377191D151C0E8E21A80081520C00000000000000840	\N	\N
second_floor	\N	0.25	340	341	339	t	01020000A034BF0D0002000000755CA765853252C0C8AB83DC21FE20C00000000000000840755CA765852252C0C8AB83DC21FE20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.740104716575501698	341	337	341	t	01020000A034BF0D00030000001DB0D345E36152C0C8AB83DC21FE20C000000000000008405381ADE61A5652C0C8AB83DC21FE20C00000000000000840755CA765853252C0C8AB83DC21FE20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	1.56939305459496836	342	340	342	t	01020000A034BF0D000200000041E5377191D151C0E8E21A80081520C00000000000000840BDE1A681206D51C0E8E21A80081520C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	0.812508065997468498	343	340	343	t	01020000A034BF0D000300000041E5377191D151C0E8E21A80081520C000000000000008406D1D9B4B54EF51C02043025AE34D1EC000000000000008406D1D9B4B54EF51C0D088E7334CAF1DC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	0.452317861665538001	344	343	344	t	01020000A034BF0D00020000006D1D9B4B54EF51C0D088E7334CAF1DC000000000000008401D1F5481CC0352C0E06D57D8C8671CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	1.82371771601757882	345	343	345	t	01020000A034BF0D00040000006D1D9B4B54EF51C0D088E7334CAF1DC000000000000008409548DAE5F0E851C0503BDAD715491DC000000000000008409548DAE5F0E851C0E0B95E18678B17C00000000000000840A18F30A7BFDD51C0B02AC32D53D816C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	0.454891787035023754	346	345	346	t	01020000A034BF0D0002000000A18F30A7BFDD51C0B02AC32D53D816C000000000000008406D6DBFB4A2C051C0B02AC32D53D816C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	1.04999999600187266	347	346	347	t	01020000A034BF0D00030000006D6DBFB4A2C051C0B02AC32D53D816C000000000000008402DF9271B099F51C0B02AC32D53D816C00000000000000840398590816F7D51C0B02AC32D53D816C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lb	0.920346444524519858	348	348	349	t	01020000A034BF0D0005000000398590816F7D51C0D06BAE083BFC12C00000000000000840398590816F7D51C010A3374A9B6111C00000000000000840398590816F7D51C0507418EAB51011C00000000000000840118590816F7D51C0D07118EAB51011C00000000000000840118590816F7D51C0A0119B78979B0EC00000000000000840	\N	\N
second_floor	\N	0.0899999999993923439	349	350	348	t	01020000A034BF0D0002000000398590816F7D51C080F870FE635813C00000000000000840398590816F7D51C0D06BAE083BFC12C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	0.874935855285499997	350	347	350	t	01020000A034BF0D0003000000398590816F7D51C0B02AC32D53D816C00000000000000840398590816F7D51C040C1E7BC03F314C00000000000000840398590816F7D51C080F870FE635813C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lu	0.942059195305055441	351	351	352	t	01020000A034BF0D0005000000D33D983A013851C0D06BAE083BFC12C00000000000000840D33D983A013851C010A3374A9B6111C00000000000000840D33D983A013851C0F033A132F03E11C000000000000008405F33C196903A51C030DB1170FA1511C000000000000008405F33C196903A51C0E03EA86C0E910EC00000000000000840	\N	\N
second_floor	\N	0.0899999999993923439	352	353	351	t	01020000A034BF0D0002000000D33D983A013851C080F870FE635813C00000000000000840D33D983A013851C0D06BAE083BFC12C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	1.70199870912001217	353	347	353	t	01020000A034BF0D0006000000398590816F7D51C0B02AC32D53D816C00000000000000840F110F9E7D55B51C0B02AC32D53D816C00000000000000840AD8D2C802B5451C0B02AC32D53D816C00000000000000840D33D983A013851C0202D7ED4AE1515C00000000000000840D33D983A013851C040C1E7BC03F314C00000000000000840D33D983A013851C080F870FE635813C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lc	0.920346444524489327	354	354	355	t	01020000A034BF0D00050000006D6DBFB4A2C051C0D06BAE083BFC12C000000000000008406D6DBFB4A2C051C010A3374A9B6111C000000000000008406D6DBFB4A2C051C0D07318EAB51011C000000000000008404F6DBFB4A2C051C0F07118EAB51011C000000000000008404F6DBFB4A2C051C060119B78979B0EC00000000000000840	\N	\N
second_floor	\N	0.0899999999993923439	355	356	354	t	01020000A034BF0D00020000006D6DBFB4A2C051C080F870FE635813C000000000000008406D6DBFB4A2C051C0D06BAE083BFC12C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	0.874935855285499997	356	346	356	t	01020000A034BF0D00030000006D6DBFB4A2C051C0B02AC32D53D816C000000000000008406D6DBFB4A2C051C040C1E7BC03F314C000000000000008406D6DBFB4A2C051C080F870FE635813C00000000000000840	\N	\N
second_floor	\N	0.0225805231300776586	357	357	358	t	01020000A034BF0D0002000000D34E483C5E0552C080F870FE635813C000000000000008401D5111D6630652C0E0D3E0610A4813C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	1.13135645983353728	358	345	357	t	01020000A034BF0D0005000000A18F30A7BFDD51C0B02AC32D53D816C000000000000008406DE1564E3CE251C0000E5EBB889016C00000000000000840ABCB273A3C0152C0206A4FFE89A014C00000000000000840ABCB273A3C0152C0002B7920849A13C00000000000000840D34E483C5E0552C080F870FE635813C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	0.311172288924506435	359	359	360	t	01020000A034BF0D00030000006753DA6F690752C080F870FE635813C000000000000008408988E9A0BB1352C0904A640F871D14C00000000000000840898BBC2C391652C0904A640F871D14C00000000000000840	\N	\N
second_floor	\N	0.0225805231300776586	360	358	359	t	01020000A034BF0D00020000001D5111D6630652C0E0D3E0610A4813C000000000000008406753DA6F690752C080F870FE635813C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lZ	0.936812411220175556	361	361	362	t	01020000A034BF0D00050000001D5111D6630652C02069AE083BFC12C000000000000008401D5111D6630652C060A0374A9B6111C000000000000008401D5111D6630652C06070078DC23911C00000000000000840475BE879D40352C0001378CACC1011C00000000000000840475BE879D40352C060AB1840CD9B0EC00000000000000840	\N	\N
second_floor	\N	0.074033158971985813	362	358	361	t	01020000A034BF0D00020000001D5111D6630652C0E0D3E0610A4813C000000000000008401D5111D6630652C02069AE083BFC12C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.60279257407976017	363	320	363	t	01020000A034BF0D0003000000BB735325F37350C078C1BEBCD0A727C0000000000000084099AA3DB0479850C0880A6D652C8526C0000000000000084099AA3DB0479850C0F070D3CB92EB20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lf	2.57763976583958332	364	364	365	t	01020000A034BF0D0005000000AEC273CF07EC4FC0E849C9C798C22CC00000000000000840AEC273CF07EC4FC0F04E64329E912DC00000000000000840D23CD6B41FE84FC06066DA9C3EA12DC00000000000000840F2E190901FE84FC0E8ED6ED4A3CF2DC0000000000000084092957199842F4FC0407371D3FE5830C00000000000000840	\N	\N
second_floor	\N	0.199662503876993469	365	366	364	t	01020000A034BF0D0002000000AEC273CF07EC4FC0A882E09D5E5C2CC00000000000000840AEC273CF07EC4FC0E849C9C798C22CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.35264495408100061	366	319	366	t	01020000A034BF0D0003000000AEC273CF07EC4FC078C1BEBCD0A727C00000000000000840AEC273CF07EC4FC0B85BAF95B23F2BC00000000000000840AEC273CF07EC4FC0A882E09D5E5C2CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lf	1.00507820220856714	367	365	367	t	01020000A034BF0D000200000092957199842F4FC0407371D3FE5830C0000000000000084046EE2307832F4FC0B8F184A14B5A31C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lf	2.44402523131375293	368	367	368	t	01020000A034BF0D000300000046EE2307832F4FC0B8F184A14B5A31C000000000000008406A2EAB61AB534EC0747176ECFA1133C0000000000000084002377E00BD514EC0747176ECFA1133C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lf	1.63523659334367766	369	367	369	t	01020000A034BF0D000500000046EE2307832F4FC0B8F184A14B5A31C0000000000000084092032CB724304FC084AB7B098F5B31C00000000000000840CED4E12623304FC06425F029925B32C00000000000000840CA0EAB76EE344FC0E01B7B05296532C0000000000000084066B76A90ED344FC03C09A0E36BF832C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lf	0.691453692809355314	370	365	370	t	01020000A034BF0D000300000092957199842F4FC0407371D3FE5830C0000000000000084042BB83FCD6FF4EC0487D2B3347F32FC000000000000008404A4575C6C2EA4EC0487D2B3347F32FC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.66046322993175144	371	318	371	t	01020000A034BF0D0005000000E2C9D754D2004EC068EA1A4C939D25C000000000000008406E93B35419AB4DC098108A4BAF4624C000000000000008406E93B35419AB4DC07808F2107FA721C000000000000008403AF6335C46984DC0A893F32E335C21C000000000000008403AF6335C46984DC01084700FA3F820C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	1.46276510858943487	372	372	373	t	01020000A034BF0D0004000000A2A11379631F4EC01084700FA3F820C000000000000008405EEB1F7B8E664EC01084700FA3F820C000000000000008407A4584B66D864EC01084700FA3F820C000000000000008400A196671F6C14EC0C035E923800A20C00000000000000840	\N	\N
second_floor	\N	0.24557595177998337	373	374	372	t	01020000A034BF0D000200000082D7AE70F4FF4DC01084700FA3F820C00000000000000840A2A11379631F4EC01084700FA3F820C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.810000000000002274	374	371	374	t	01020000A034BF0D00030000003AF6335C46984DC01084700FA3F820C00000000000000840C68DA26EC9B84DC01084700FA3F820C0000000000000084082D7AE70F4FF4DC01084700FA3F820C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	1.55894712300903393	375	373	375	t	01020000A034BF0D00020000000A196671F6C14EC0C035E923800A20C000000000000008403ADBB40582894FC0C035E923800A20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	0.80622524884276614	376	373	376	t	01020000A034BF0D00030000000A196671F6C14EC0C035E923800A20C000000000000008407E87972A08874EC010DF5D118E3D1EC000000000000008407E87972A08874EC090AF1EB1B49E1DC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	1.8189075880607759	377	376	377	t	01020000A034BF0D00060000007E87972A08874EC090AF1EB1B49E1DC0000000000000084046341E279A904EC05049E9CC24521DC0000000000000084046341E279A904EC05049E9CC24521CC00000000000000840C6B3B7C033924EC0504D1D0058451CC00000000000000840C6B3B7C033924EC0D0EDF74D105A17C000000000000008403637CF3EBAA54EC050D23B5DDCBD16C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	0.500186748687241334	378	377	378	t	01020000A034BF0D00020000003637CF3EBAA54EC050D23B5DDCBD16C00000000000000840C2F75E5DC0E54EC050D23B5DDCBD16C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	1.0499999960019295	379	378	379	t	01020000A034BF0D0003000000C2F75E5DC0E54EC050D23B5DDCBD16C0000000000000084022E08D90F3284FC050D23B5DDCBD16C0000000000000084032C8BCC3266C4FC050D23B5DDCBD16C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lo	0.961856137703103187	380	380	381	t	01020000A034BF0D0005000000A681797AB7F54FC040599F9BB6E112C00000000000000840B681797AB7F54FC0809028DD164711C00000000000000840B2FD58403CF74FC0C0B02CAEF03A11C000000000000008401A9627C298F04FC00074A1BCD40511C000000000000008401A9627C298F04FC0808FD5649B470EC00000000000000840	\N	\N
second_floor	\N	0.090000000000358682	381	382	380	t	01020000A034BF0D0002000000A281797AB7F54FC030EA6191DF3D13C00000000000000840A681797AB7F54FC040599F9BB6E112C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	1.68596100092194856	382	379	382	t	01020000A034BF0D000600000032C8BCC3266C4FC050D23B5DDCBD16C000000000000008409AB0EBF659AF4FC050D23B5DDCBD16C000000000000008409E158C6415BC4FC050D23B5DDCBD16C000000000000008409281797AB7F54FC0C072D0ADCBF014C000000000000008409281797AB7F54FC0F0B2D84F7FD814C00000000000000840A281797AB7F54FC030EA6191DF3D13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048ln	0.952910487115769422	383	383	384	t	01020000A034BF0D000500000046C8BCC3266C4FC040599F9BB6E112C0000000000000084056C8BCC3266C4FC0809028DD164711C0000000000000084072BBBE1935714FC0C0F7182DA41E11C000000000000008405EC8BCC3266C4FC0205F097D31F610C000000000000008405EC8BCC3266C4FC040B905E4E1660EC00000000000000840	\N	\N
second_floor	\N	0.090000000000358682	384	385	383	t	01020000A034BF0D000200000042C8BCC3266C4FC030EA6191DF3D13C0000000000000084046C8BCC3266C4FC040599F9BB6E112C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	0.874987778830501384	385	379	385	t	01020000A034BF0D000300000032C8BCC3266C4FC050D23B5DDCBD16C0000000000000084032C8BCC3266C4FC0F0B2D84F7FD814C0000000000000084042C8BCC3266C4FC030EA6191DF3D13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lq	0.952910487115782523	386	386	387	t	01020000A034BF0D0005000000D6F75E5DC0E54EC040599F9BB6E112C00000000000000840EAF75E5DC0E54EC0809028DD164711C00000000000000840FAEA60B3CEEA4EC010F8182DA41E11C00000000000000840E6F75E5DC0E54EC0605F097D31F610C00000000000000840E6F75E5DC0E54EC0C0B805E4E1660EC00000000000000840	\N	\N
second_floor	\N	0.090000000000358682	387	388	386	t	01020000A034BF0D0002000000D2F75E5DC0E54EC030EA6191DF3D13C00000000000000840D6F75E5DC0E54EC040599F9BB6E112C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	0.874987778830501384	388	378	388	t	01020000A034BF0D0003000000C2F75E5DC0E54EC050D23B5DDCBD16C00000000000000840C2F75E5DC0E54EC0F0B2D84F7FD814C00000000000000840D2F75E5DC0E54EC030EA6191DF3D13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lB	0.952486239310288418	389	389	390	t	01020000A034BF0D0007000000FAF10F4A34644EC040599F9BB6E112C00000000000000840FEF10F4A34644EC070CC836B12CA11C00000000000000840B60F302A8D624EC010BA846CD9BC11C00000000000000840BA0F302A8D624EC0709028DD164711C00000000000000840AA8E9AE601664EC00099D4F9702B11C0000000000000084026C4F309175E4EC0E0449E141AEC10C0000000000000084026C4F309175E4EC0C0EDDBB4107B0EC00000000000000840	\N	\N
second_floor	\N	0.090000000000358682	390	391	389	t	01020000A034BF0D0002000000FAF10F4A34644EC030EA6191DF3D13C00000000000000840FAF10F4A34644EC040599F9BB6E112C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	1.0870239143252507	391	377	391	t	01020000A034BF0D00060000003637CF3EBAA54EC050D23B5DDCBD16C00000000000000840A20F302A8DA24EC0B09542B873A416C000000000000008406E71A9E3CD654EC020A40D8479BE14C000000000000008407671A9E3CD654EC040FF09E051C713C00000000000000840F6F10F4A34644EC030033E1385BA13C00000000000000840FAF10F4A34644EC030EA6191DF3D13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	0.438053546813286288	392	376	392	t	01020000A034BF0D00020000007E87972A08874EC090AF1EB1B49E1DC00000000000000840662FF341625F4EC0D0EEFB6B85611CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.580499591417009242	393	371	393	t	01020000A034BF0D00020000003AF6335C46984DC01084700FA3F820C000000000000008403AF6335C46984DC0401FBFA2D79E1FC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.26200636282128364	394	316	394	t	01020000A034BF0D0004000000E675459C60B34DC0980705A102E425C000000000000008408226E87938914DC0980705A102E425C00000000000000840724E5296058E4DC068A7AD1237D725C00000000000000840F6B180612A134CC068A7AD1237D725C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.3199890916921504	395	394	395	t	01020000A034BF0D0002000000F6B180612A134CC068A7AD1237D725C0000000000000084076BF72FA34EA4AC068A7AD1237D725C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.45180680600108891	396	395	396	t	01020000A034BF0D000300000076BF72FA34EA4AC068A7AD1237D725C00000000000000840424BE702AE954AC068A7AD1237D725C000000000000008402230B0040C4E4AC0E0138A0BBFF526C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.523780672107459488	397	396	397	t	01020000A034BF0D00020000002230B0040C4E4AC0E0138A0BBFF526C000000000000008406AA776C5A31E4AC0C836700860B327C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.28957874988998356	398	397	398	t	01020000A034BF0D00020000006AA776C5A31E4AC0C836700860B327C00000000000000840FA74D8DA927948C0C836700860B327C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15905238501267149	399	398	399	t	01020000A034BF0D0002000000FA74D8DA927948C0C836700860B327C000000000000008408277BC0637E547C0C836700860B327C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.16094761498732169	400	399	400	t	01020000A034BF0D00020000008277BC0637E547C0C836700860B327C00000000000000840D21849189D5047C0C836700860B327C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6LG	3.9233383377832256	401	401	402	t	01020000A034BF0D0006000000D21849189D5047C0A8FCC28A664523C00000000000000840D21849189D5047C058F72720617622C00000000000000840C2EB967AAD5047C098ABF0961F7622C00000000000000840C2EB967AAD5047C07821C90BFC2822C000000000000008401AFAC32C4B9847C028E81443850A21C000000000000008401AFAC32C4B9847C090237F4BD4C617C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.10008630144700703	403	400	403	t	01020000A034BF0D0003000000D21849189D5047C0C836700860B327C00000000000000840D21849189D5047C09061A28DCD9C24C00000000000000840D21849189D5047C0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.0390523850126669458	404	400	404	t	01020000A034BF0D0002000000D21849189D5047C0C836700860B327C00000000000000840EADD226D9D4B47C0C836700860B327C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.854913698552337564	405	404	405	t	01020000A034BF0D0002000000EADD226D9D4B47C0C836700860B327C0000000000000084046C63E9D2FDE46C0C836700860B327C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.432797315168529095	406	405	406	t	01020000A034BF0D000200000046C63E9D2FDE46C0C836700860B327C00000000000000840387FAF7E03B746C0901A338EAF1627C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Ml	3.95795003603080264	407	407	408	t	01020000A034BF0D000A000000387FAF7E03B746C058FCC28A664523C00000000000000840387FAF7E03B746C060F72720617622C0000000000000084046AC611CF3B646C098ABF0961F7622C0000000000000084046AC611CF3B646C03021C90BFC2822C000000000000008408C913B58F27746C048B630FBF82C21C000000000000008408C913B58F27746C0D84B81AC2F3120C0000000000000084096D259B35A6846C000A0F431A2E51FC0000000000000084096D259B35A6846C0B07EFB3D107418C00000000000000840685F59C0606E46C02018FFD5DF4318C00000000000000840685F59C0606E46C07018599A79CE17C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	408	409	407	t	01020000A034BF0D0002000000387FAF7E03B746C0A03A7185218023C00000000000000840387FAF7E03B746C058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.7940523850120087	409	406	409	t	01020000A034BF0D0003000000387FAF7E03B746C0901A338EAF1627C00000000000000840387FAF7E03B746C09061A28DCD9C24C00000000000000840387FAF7E03B746C0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.10579208869931866	410	406	410	t	01020000A034BF0D0003000000387FAF7E03B746C0901A338EAF1627C00000000000000840AA2CA503966446C058D009A2F9CC25C00000000000000840085C4E6B9D4B45C058D009A2F9CC25C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Mg	5.12462571842970682	411	411	412	t	01020000A034BF0D000B000000085C4E6B9D4B45C058FCC28A664523C00000000000000840085C4E6B9D4B45C068D59182BA2822C00000000000000840085C4E6B9D4B45C0889FD399B3DF21C00000000000000840D2F5B3AACED444C0B0066A97780420C00000000000000840D2F5B3AACED444C0803875915E111EC000000000000008408A14399620E544C0C0424C35CF8E1DC000000000000008408A14399620E544C0F0DBA33AE3CA1AC00000000000000840E2F6044670DE44C0B0EE02B960951AC00000000000000840E2F6044670DE44C000EF5C7DFA1F1AC000000000000008408E522D8DDA6A45C0A0111A44A8BC15C000000000000008408E522D8DDA6A45C0B0E176D36AB215C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	412	413	411	t	01020000A034BF0D0002000000085C4E6B9D4B45C0A03A7185218023C00000000000000840085C4E6B9D4B45C058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144698998	413	410	413	t	01020000A034BF0D0003000000085C4E6B9D4B45C058D009A2F9CC25C00000000000000840085C4E6B9D4B45C09061A28DCD9C24C00000000000000840085C4E6B9D4B45C0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	4.29999999999999716	414	410	414	t	01020000A034BF0D0002000000085C4E6B9D4B45C058D009A2F9CC25C00000000000000840A2F5E704372543C058D009A2F9CC25C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Mf	3.18415612345224641	415	415	416	t	01020000A034BF0D0009000000A2F5E704372543C058FCC28A664523C00000000000000840A2F5E704372543C068D59182BA2822C00000000000000840A2F5E704372543C0F03F04E37F1120C0000000000000084082D60EB5A52843C070BC6822C50320C0000000000000084082D60EB5A52843C080165DAB600F1EC00000000000000840CAB789C9531843C0C020344FD18C1DC00000000000000840CAB789C9531843C0D0507400A2CB1AC000000000000008400C525BF8121F43C0C07EE789A8951AC000000000000008400C525BF8121F43C0A036C52A09261AC00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	416	417	415	t	01020000A034BF0D0002000000A2F5E704372543C0A03A7185218023C00000000000000840A2F5E704372543C058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144698998	417	414	417	t	01020000A034BF0D0003000000A2F5E704372543C058D009A2F9CC25C00000000000000840A2F5E704372543C09061A28DCD9C24C00000000000000840A2F5E704372543C0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.70134294243050022	418	414	418	t	01020000A034BF0D0002000000A2F5E704372543C058D009A2F9CC25C000000000000008402673E369714B41C058D009A2F9CC25C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Ma	3.23097174319741232	419	419	420	t	01020000A034BF0D00090000002673E369714B41C058FCC28A664523C000000000000008402673E369714B41C068D59182BA2822C000000000000008402673E369714B41C000E2A2F9694520C00000000000000840B25782101F3B41C030741E94200420C00000000000000840B25782101F3B41C00086C88E17101EC000000000000008406A7607FC704B41C040909F32888D1DC000000000000008406A7607FC704B41C050E1081DEBCA1AC0000000000000084070060287BF4441C08061DD745F951AC0000000000000084070060287BF4441C07081695DA1201AC00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	420	421	419	t	01020000A034BF0D00020000002673E369714B41C0A03A7185218023C000000000000008402673E369714B41C058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144698998	421	418	421	t	01020000A034BF0D00030000002673E369714B41C058D009A2F9CC25C000000000000008402673E369714B41C09061A28DCD9C24C000000000000008402673E369714B41C0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.00464200410081617	422	418	422	t	01020000A034BF0D00020000002673E369714B41C058D009A2F9CC25C00000000000000840A28CEF4DD9CA40C058D009A2F9CC25C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.39535799589918952	423	422	423	t	01020000A034BF0D0002000000A28CEF4DD9CA40C058D009A2F9CC25C00000000000000840E47F606D7C303EC058D009A2F9CC25C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MZ	5.18212757021347681	424	424	425	t	01020000A034BF0D000C000000E47F606D7C303EC058FCC28A664523C00000000000000840E47F606D7C303EC068D59182BA2822C00000000000000840E47F606D7C303EC0207B3C9303DF21C000000000000008406083EFECED1D3FC028741E94200420C000000000000008406083EFECED1D3FC0405F0AD9720F1EC00000000000000840F045E5154AFD3EC08069E17CE38C1DC00000000000000840F045E5154AFD3EC020C6D6F842CA1AC00000000000000840DC6753BCC60A3FC0703E1E5F50941AC00000000000000840DC6753BCC60A3FC090112E2459251AC0000000000000084000714B1FBF8C3FC000ED4D98771D18C000000000000008400AC1ECAFF11740C0B0A81596E69015C000000000000008400AC1ECAFF11740C0C010C4DDC78B15C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	425	426	424	t	01020000A034BF0D0002000000E47F606D7C303EC0A03A7185218023C00000000000000840E47F606D7C303EC058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144698998	426	423	426	t	01020000A034BF0D0003000000E47F606D7C303EC058D009A2F9CC25C00000000000000840E47F606D7C303EC09061A28DCD9C24C00000000000000840E47F606D7C303EC0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.10308066398400362	427	423	427	t	01020000A034BF0D0003000000E47F606D7C303EC058D009A2F9CC25C000000000000008409CC3B1EA53FC3BC058D009A2F9CC25C00000000000000840F45BF6C287593BC0A89F80F1911227C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.401738954249359848	428	427	428	t	01020000A034BF0D0002000000F45BF6C287593BC0A89F80F1911227C00000000000000840AC71F9CBCE103BC038747ADF03A427C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.876277176621883314	429	428	429	t	01020000A034BF0D0002000000AC71F9CBCE103BC038747ADF03A427C00000000000000840309F81187B303AC038747ADF03A427C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.0396504845615908152	430	429	430	t	01020000A034BF0D0002000000309F81187B303AC038747ADF03A427C00000000000000840C428C38F54263AC038747ADF03A427C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Mz	3.91833833780180285	431	431	432	t	01020000A034BF0D0006000000C428C38F54263AC088FDC28A664523C00000000000000840C428C38F54263AC070F72720617622C00000000000000840248327CB33263AC038ACF0961F7622C00000000000000840248327CB33263AC0D821C90BFC2822C00000000000000840C066CD66F89639C008E91443850A21C00000000000000840C066CD66F89639C030BED003F3CB17C00000000000000840	\N	\N
second_floor	\N	0.114707788247457643	432	433	431	t	01020000A034BF0D0002000000C428C38F54263AC0A03A7185218023C00000000000000840C428C38F54263AC088FDC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.07008630144700589	433	430	433	t	01020000A034BF0D0003000000C428C38F54263AC038747ADF03A427C00000000000000840C428C38F54263AC09061A28DCD9C24C00000000000000840C428C38F54263AC0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.16034951543841203	434	430	434	t	01020000A034BF0D0002000000C428C38F54263AC038747ADF03A427C00000000000000840FC6B4EE547FD38C038747ADF03A427C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15965048456159536	435	434	435	t	01020000A034BF0D0002000000FC6B4EE547FD38C038747ADF03A427C000000000000008407070A40A69D437C038747ADF03A427C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Mu	3.95762947996184522	436	436	437	t	01020000A034BF0D000A0000007070A40A69D437C058FCC28A664523C000000000000008407070A40A69D437C070F72720617622C0000000000000084044CA084648D437C018ABF0961F7622C0000000000000084044CA084648D437C0C021C90BFC2822C00000000000000840C8AEFDEA485637C0C8EAB255FD2C21C00000000000000840C8AEFDEA485637C0404666F63C3020C000000000000008405871F313A53537C0C096A390EADD1FC000000000000008405871F313A53537C0605C789CEB7718C000000000000008403C1A9971234337C0D0B8E125F24118C000000000000008403C1A9971234337C0700827C498D317C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	437	438	436	t	01020000A034BF0D00020000007070A40A69D437C0A03A7185218023C000000000000008407070A40A69D437C058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.07008630144700589	438	435	438	t	01020000A034BF0D00030000007070A40A69D437C038747ADF03A427C000000000000008407070A40A69D437C09061A28DCD9C24C000000000000008407070A40A69D437C0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.32389973592249532	439	435	439	t	01020000A034BF0D00020000007070A40A69D437C038747ADF03A427C000000000000008401478CFF27D8134C038747ADF03A427C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.503508032058706312	440	439	440	t	01020000A034BF0D00020000001478CFF27D8134C038747ADF03A427C00000000000000840645D6EE8582634C0D83EB8CAB9ED26C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Mt	3.9622646719017891	441	441	442	t	01020000A034BF0D000A000000645D6EE8582634C058FCC28A664523C00000000000000840645D6EE8582634C078F72720617622C000000000000008400C030AAD792634C028ACF0961F7622C000000000000008400C030AAD792634C0B820C90BFC2822C00000000000000840D49034925FA434C030057441302D21C00000000000000840D49034925FA434C0A86027E26F3020C0000000000000084044CE3E6903C534C090CB256850DE1FC0000000000000084044CE3E6903C534C09027F6C4857718C00000000000000840AC62367FA0B734C03079D41CFA4118C00000000000000840AC62367FA0B734C0E030C80282CE17C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	442	443	441	t	01020000A034BF0D0002000000645D6EE8582634C0A03A7185218023C00000000000000840645D6EE8582634C058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.71405235759640107	443	440	443	t	01020000A034BF0D0003000000645D6EE8582634C0D83EB8CAB9ED26C00000000000000840645D6EE8582634C09061A28DCD9C24C00000000000000840645D6EE8582634C0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.43360238917515526	444	440	444	t	01020000A034BF0D0003000000645D6EE8582634C0D83EB8CAB9ED26C00000000000000840242617D4F89533C058D009A2F9CC25C00000000000000840302A3BB525F332C058D009A2F9CC25C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.32205279391750707	445	444	445	t	01020000A034BF0D0002000000302A3BB525F332C058D009A2F9CC25C0000000000000084024B4F1A7B3A030C058D009A2F9CC25C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.9178310959694298	446	445	446	t	01020000A034BF0D000500000024B4F1A7B3A030C058D009A2F9CC25C0000000000000084018027883EFD92AC058D009A2F9CC25C00000000000000840005430A274C52AC0707E518374E125C00000000000000840409B7122B0CE29C0707E518374E125C0000000000000084070E5CB16888E29C0A0C8AB774CA125C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.93730044359985509	447	446	447	t	01020000A034BF0D000300000070E5CB16888E29C0A0C8AB774CA125C00000000000000840309E8A964C8526C0A0C8AB774CA125C00000000000000840F8788019788324C0D8EDB5F420A327C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.947386558761976971	448	447	448	t	01020000A034BF0D0002000000F8788019788324C0D8EDB5F420A327C00000000000000840005EA33F689E22C0D8EDB5F420A327C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.4578409906098031	449	448	449	t	01020000A034BF0D0003000000005EA33F689E22C0D8EDB5F420A327C00000000000000840307E2672317617C0D8EDB5F420A327C0000000000000084060347A8B256C17C0F0C85F011B9E27C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.667420586134525706	450	449	450	t	01020000A034BF0D000200000060347A8B256C17C0F0C85F011B9E27C0000000000000084070B4213EB5C014C0F0C85F011B9E27C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.62163611922146345	451	450	451	t	01020000A034BF0D000200000070B4213EB5C014C0F0C85F011B9E27C0000000000000084080DCB2204E8804C0F0C85F011B9E27C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	5.61584703285852438	452	451	452	t	01020000A034BF0D000800000080DCB2204E8804C0F0C85F011B9E27C0000000000000084040EC9874CF43FCBF582FC667810426C000000000000008400010C12DEE49CFBF582FC667810426C00000000000000840001AE6296770CABF582FC667810426C00000000000000840006C7057943EE53F3090A785D64624C00000000000000840006C7057943EE53F3871BE76A2A421C00000000000000840004C1A109A22E93F38D3331B626621C00000000000000840004C1A109A22E93F28897F828FFD20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	1.42077893475734118	453	453	454	t	01020000A034BF0D00040000000010C12DEE49CFBF28897F828FFD20C000000000000008400023C0181341E6BF28897F828FFD20C00000000000000840402BE47CB0A0F0BF28897F828FFD20C0000000000000084040BDD35CC1B5F7BFE8968166ED1A20C00000000000000840	\N	\N
second_floor	\N	0.25	454	455	453	t	01020000A034BF0D00020000000000DE473AC2763F28897F828FFD20C000000000000008400010C12DEE49CFBF28897F828FFD20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.779917529860995273	455	452	455	t	01020000A034BF0D0003000000004C1A109A22E93F28897F828FFD20C000000000000008400037BF033838DD3F28897F828FFD20C000000000000008400000DE473AC2763F28897F828FFD20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	1.64072386883400156	456	454	456	t	01020000A034BF0D000200000040BDD35CC1B5F7BFE8968166ED1A20C0000000000000084080235D8414FB08C0E8968166ED1A20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	0.833029560556820092	457	454	457	t	01020000A034BF0D000300000040BDD35CC1B5F7BFE8968166ED1A20C0000000000000084080F5B51E2CD5F0BFF0BB7B7DB57D1EC0000000000000084080F5B51E2CD5F0BFE088E89125971DC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	1.78292440942558983	458	457	458	t	01020000A034BF0D000400000080F5B51E2CD5F0BFE088E89125971DC00000000000000840C03593FF666FF2BFD038B1D996301DC00000000000000840C03593FF666FF2BF802C0BADBDAB17C0000000000000084000172739EF64F5BF4034A69E5BEE16C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	0.4276658036609291	459	458	459	t	01020000A034BF0D000200000000172739EF64F5BF4034A69E5BEE16C00000000000000840C08C2C52A73CFCBF4034A69E5BEE16C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	1.04999999600188687	460	459	460	t	01020000A034BF0D0003000000C08C2C52A73CFCBF4034A69E5BEE16C00000000000000840C0CA04DC865102C04034A69E5BEE16C00000000000000840004DF30EBA8406C04034A69E5BEE16C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lL	0.954043667811909302	461	461	462	t	01020000A034BF0D00050000008060E6C8A14C0FC0208876BC630013C000000000000008408060E6C8A14C0FC060BFFFFDC36511C000000000000008408060E6C8A14C0FC0803FF478093611C0000000000000084040A9C743B6FA0EC0E0E364B6130D11C0000000000000084040A9C743B6FA0EC080A98C83D4800EC00000000000000840	\N	\N
second_floor	\N	0.0899999999999323563	462	463	461	t	01020000A034BF0D00020000008060E6C8A14C0FC0301739B28C5C13C000000000000008408060E6C8A14C0FC0208876BC630013C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	1.72945421111938025	463	460	463	t	01020000A034BF0D0006000000004DF30EBA8406C04034A69E5BEE16C0000000000000084040D2E141EDB70AC04034A69E5BEE16C00000000000000840E0B61077B8BD0BC04034A69E5BEE16C000000000000008408060E6C8A14C0FC0705FBBF5E62615C000000000000008408060E6C8A14C0FC0F0DFAF702CF714C000000000000008408060E6C8A14C0FC0301739B28C5C13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lM	0.945085081031279639	464	464	465	t	01020000A034BF0D0005000000004DF30EBA8406C0208876BC630013C00000000000000840004DF30EBA8406C060BFFFFDC36511C00000000000000840004DF30EBA8406C0008FE09DDE1411C00000000000000840804EF30EBA8406C0408EE09DDE1411C00000000000000840804EF30EBA8406C0C05495B43E710EC00000000000000840	\N	\N
second_floor	\N	0.0899999999999323563	465	466	464	t	01020000A034BF0D0002000000004DF30EBA8406C0301739B28C5C13C00000000000000840004DF30EBA8406C0208876BC630013C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	0.892390913162003585	466	460	466	t	01020000A034BF0D0003000000004DF30EBA8406C04034A69E5BEE16C00000000000000840004DF30EBA8406C0F0DFAF702CF714C00000000000000840004DF30EBA8406C0301739B28C5C13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lJ	0.94508508103123845	467	467	468	t	01020000A034BF0D0005000000C08C2C52A73CFCBF208876BC630013C00000000000000840C08C2C52A73CFCBF60BFFFFDC36511C00000000000000840C08C2C52A73CFCBF908EE09DDE1411C00000000000000840008E2C52A73CFCBF408EE09DDE1411C00000000000000840008E2C52A73CFCBFC05495B43E710EC00000000000000840	\N	\N
second_floor	\N	0.0899999999999323563	468	469	467	t	01020000A034BF0D0002000000C08C2C52A73CFCBF301739B28C5C13C00000000000000840C08C2C52A73CFCBF208876BC630013C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	0.892390913162003585	469	459	469	t	01020000A034BF0D0003000000C08C2C52A73CFCBF4034A69E5BEE16C00000000000000840C08C2C52A73CFCBFF0DFAF702CF714C00000000000000840C08C2C52A73CFCBF301739B28C5C13C00000000000000840	\N	\N
second_floor	\N	0.0429537524212110847	470	470	471	t	01020000A034BF0D000300000000B15DBEEEBAE8BF301739B28C5C13C0000000000000084000B15DBEEEBAE8BF604FF6650A5913C000000000000008400092B9B7F7D5E7BF80CB21856B3C13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	1.12614127079994719	471	458	470	t	01020000A034BF0D000600000000172739EF64F5BF4034A69E5BEE16C0000000000000084000864FEC40D6F3BF1050700BB08A16C00000000000000840808E2A5D2E73E9BF60C0019C85C314C00000000000000840808E2A5D2E73E9BFD0E0F8B5A13214C0000000000000084000B15DBEEEBAE8BF20451FC2991B14C0000000000000084000B15DBEEEBAE8BF301739B28C5C13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lS	0.961965972508309508	472	472	473	t	01020000A034BF0D00050000000092B9B7F7D5E7BF208876BC630013C000000000000008400092B9B7F7D5E7BF60BFFFFDC36511C000000000000008400092B9B7F7D5E7BFE01F3BF3A63311C00000000000000840007834CCA51DE7BFA07CCAB59C1C11C00000000000000840007834CCA51DE7BF0078C184C2610EC00000000000000840	\N	\N
second_floor	\N	0.0586234430819274621	473	471	472	t	01020000A034BF0D00020000000092B9B7F7D5E7BF80CB21856B3C13C000000000000008400092B9B7F7D5E7BF208876BC630013C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	0.355302154765635703	474	474	475	t	01020000A034BF0D00030000008034FF4EEED4E6BF301739B28C5C13C0000000000000084000408109F4EAE0BFB0D5E8FACB1914C00000000000000840002DA4B8CFD2DBBFB0D5E8FACB1914C00000000000000840	\N	\N
second_floor	\N	0.0443731523340138781	475	471	474	t	01020000A034BF0D00020000000092B9B7F7D5E7BF80CB21856B3C13C000000000000008408034FF4EEED4E6BF301739B28C5C13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	0.512835680985825326	476	457	476	t	01020000A034BF0D000200000080F5B51E2CD5F0BFE088E89125971DC000000000000008408003FADFAE0FE6BFF04B3A66D0231CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.680433642555001938	477	452	477	t	01020000A034BF0D0002000000004C1A109A22E93F28897F828FFD20C00000000000000840004C1A109A22E93F8095376C5B421FC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lQ	2.47172150532520174	478	478	479	t	01020000A034BF0D00040000004069437C6A810CC060D06649BBDE2CC000000000000008404069437C6A810CC050F7975167FB2DC000000000000008404069437C6A810CC0309D3316886B2EC00000000000000840207863FE4CE802C0BCCCD5BAE76830C00000000000000840	\N	\N
second_floor	\N	0.257445718287996783	479	480	478	t	01020000A034BF0D00020000004069437C6A810CC0C8BA8D5CEB5A2CC000000000000008404069437C6A810CC060D06649BBDE2CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.91313261121472822	480	451	480	t	01020000A034BF0D000600000080DCB2204E8804C0F0C85F011B9E27C00000000000000840E05CDC2E214303C0D868D53D66EF27C00000000000000840E05CDC2E214303C0F0161D1FE10328C000000000000008404069437C6A810CC008DA767273532AC000000000000008404069437C6A810CC0D8935C543F3E2BC000000000000008404069437C6A810CC0C8BA8D5CEB5A2CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lQ	0.49045160207700178	481	479	481	t	01020000A034BF0D0002000000207863FE4CE802C0BCCCD5BAE76830C00000000000000840207863FE4CE802C0C4FD4CF775E630C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lQ	2.19819636366508453	482	481	482	t	01020000A034BF0D0003000000207863FE4CE802C0C4FD4CF775E630C00000000000000840800ABFD434D6ECBF747473F0CD5C32C00000000000000840802FA1F870ABE8BF747473F0CD5C32C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lQ	0.764264763208236775	483	481	483	t	01020000A034BF0D0003000000207863FE4CE802C0C4FD4CF775E630C0000000000000084040C6E66CB0FC02C088671D6502E930C0000000000000084040C6E66CB0FC02C0FC189D930EA931C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lQ	3.64489919105270133	484	483	484	t	01020000A034BF0D000200000040C6E66CB0FC02C0FC189D930EA931C0000000000000084040C6E66CB0FC02C0C4E2A3B0264E35C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lQ	0.174547963211470591	485	484	485	t	01020000A034BF0D000300000040C6E66CB0FC02C0C4E2A3B0264E35C00000000000000840E0DC705854D902C0EC9F3233925235C0000000000000084000CA6284DCA501C0EC9F3233925235C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lQ	0.287546116162318677	486	484	486	t	01020000A034BF0D000500000040C6E66CB0FC02C0C4E2A3B0264E35C00000000000000840C0BCDF82F46203C094016333EF5A35C00000000000000840C0BCDF82F46203C0508E7B114A5C35C00000000000000840E0BDD788106302C02C8EBC90467C35C00000000000000840E0BDD788106302C0AC98E401388535C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lD	1.79809885877850206	487	487	488	t	01020000A034BF0D00030000006050BBD74E5A12C0FC189D930EA931C00000000000000840409E1DE8A69314C0FC189D930EA931C00000000000000840400781AB8F8B19C0FC189D930EA931C00000000000000840	\N	\N
second_floor	\N	0.250000000000483169	488	489	487	t	01020000A034BF0D0002000000404EBBD74E5A11C0FC189D930EA931C000000000000008406050BBD74E5A12C0FC189D930EA931C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lQ	1.96480800630050112	489	483	489	t	01020000A034BF0D000300000040C6E66CB0FC02C0FC189D930EA931C00000000000000840C000B28EED410EC0FC189D930EA931C00000000000000840404EBBD74E5A11C0FC189D930EA931C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lD	1.92035734862469099	490	488	490	t	01020000A034BF0D0002000000400781AB8F8B19C0FC189D930EA931C00000000000000840400781AB8F8B19C0EC12A61DAB9433C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l7	1.27613336202120209	491	491	492	t	01020000A034BF0D0004000000F05DA33F68DE20C0A4D0749DE5AC35C0000000000000084050C2DE1EB8AB21C0A4D0749DE5AC35C0000000000000084030243411B0CE21C0A4D0749DE5AC35C00000000000000840308A991BCBF222C0A483A722F33E36C00000000000000840	\N	\N
second_floor	\N	0.249999999999488409	492	493	491	t	01020000A034BF0D0002000000105FA33F685E20C0A4D0749DE5AC35C00000000000000840F05DA33F68DE20C0A4D0749DE5AC35C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lD	3.67725346733186065	493	490	493	t	01020000A034BF0D0005000000400781AB8F8B19C0EC12A61DAB9433C00000000000000840400781AB8F8B19C0F0130479B94E35C0000000000000084010FA433D40041BC0A4D0749DE5AC35C0000000000000084050F5CFC030221FC0A4D0749DE5AC35C00000000000000840105FA33F685E20C0A4D0749DE5AC35C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l7	2.02896715623166379	494	492	494	t	01020000A034BF0D0006000000308A991BCBF222C0A483A722F33E36C0000000000000084028CE986A3C7223C0A483A722F33E36C00000000000000840488ADD50167623C0ACE1C915E04036C00000000000000840F097B627E37826C0ACE1C915E04036C00000000000000840F8CABD00F07D26C0244846A9593E36C00000000000000840F8CABD00F0FD26C0244846A9593E36C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l7	1.21357020913911451	495	492	495	t	01020000A034BF0D0002000000308A991BCBF222C0A483A722F33E36C0000000000000084078B7711D6F3B21C0FC6CBB21A11A37C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l0	3.52797968789575611	496	496	497	t	01020000A034BF0D0007000000F05DA33F68DE20C0EC12A61DAB9433C0000000000000084050C2DE1EB8AB21C0EC12A61DAB9433C00000000000000840F8B832025EC721C0EC12A61DAB9433C000000000000008409051437018B822C0385FAE54080D34C00000000000000840E08CC814B4EA26C0385FAE54080D34C0000000000000084018418B45642427C054B90F6DE02934C00000000000000840D84014EA1F7127C054B90F6DE02934C00000000000000840	\N	\N
second_floor	\N	0.249999999999488409	497	498	496	t	01020000A034BF0D0002000000105FA33F685E20C0EC12A61DAB9433C00000000000000840F05DA33F68DE20C0EC12A61DAB9433C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lD	1.79809885877850206	498	490	498	t	01020000A034BF0D0003000000400781AB8F8B19C0EC12A61DAB9433C0000000000000084050F5CFC030221FC0EC12A61DAB9433C00000000000000840105FA33F685E20C0EC12A61DAB9433C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.32877713142249831	499	499	450	t	01020000A034BF0D000300000070B4213EB5C014C0B00C467B70462CC0000000000000084070B4213EB5C014C0C0E51473C4292BC0000000000000084070B4213EB5C014C0F0C85F011B9E27C00000000000000840	\N	\N
second_floor	\N	0.0928257648554620118	500	500	499	t	01020000A034BF0D000200000070B4213EB5C014C0409C1657F7752CC0000000000000084070B4213EB5C014C0B00C467B70462CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lD	3.92624478699333679	501	488	500	t	01020000A034BF0D0005000000400781AB8F8B19C0FC189D930EA931C00000000000000840400781AB8F8B19C0D8BB7CE04B0730C0000000000000084070B4213EB5C014C048CE498A2AA92DC0000000000000084070B4213EB5C014C030C3475FA3922DC0000000000000084070B4213EB5C014C0409C1657F7752CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lQ	2.16480328800760979	502	479	501	t	01020000A034BF0D0005000000207863FE4CE802C0BCCCD5BAE76830C000000000000008400001287750F0FFBFCCDD7B22E30A30C0000000000000084040D91CD0328AFDBFCCDD7B22E30A30C0000000000000084000A6F784CA9EF4BFFC302EA7999930C00000000000000840004CEF09953DE9BFFC302EA7991931C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	10.1474003306424478	503	449	502	t	01020000A034BF0D000300000060347A8B256C17C0F0C85F011B9E27C00000000000000840301A9ED3BD9619C008D64DDDCE8826C00000000000000840301A9ED3BD9619C0407B8399F92BFEBF0000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.0403556115579419838	504	502	503	t	01020000A034BF0D0002000000301A9ED3BD9619C0407B8399F92BFEBF0000000000000840301A9ED3BD9619C0C0DB85ACAD86FDBF0000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.0774638183925731028	505	503	504	t	01020000A034BF0D0002000000301A9ED3BD9619C0C0DB85ACAD86FDBF0000000000000840301A9ED3BD9619C0C0F21BF96249FCBF0000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048ie	3.28566286245995709	506	505	506	t	01020000A034BF0D00050000006079F527AB7011C0C0DB85ACAD86FDBF00000000000008404061FDD216AC0FC0C0DB85ACAD86FDBF0000000000000840A01447DF18D70EC0C0DB85ACAD86FDBF0000000000000840808F772C8C7A0AC080D1E64694CDF4BF000000000000084000C3E64694CDF4BF80D1E64694CDF4BF0000000000000840	\N	\N
second_floor	\N	0.249999999999801048	507	507	505	t	01020000A034BF0D00020000008078F527AB7012C0C0DB85ACAD86FDBF00000000000008406079F527AB7011C0C0DB85ACAD86FDBF0000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.78718059746499591	508	503	507	t	01020000A034BF0D0003000000301A9ED3BD9619C0C0DB85ACAD86FDBF000000000000084030416CE64A0B14C0C0DB85ACAD86FDBF00000000000008408078F527AB7012C0C0DB85ACAD86FDBF0000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048il	3.35773400212494488	509	508	509	t	01020000A034BF0D0007000000F05DA33F68DE20C0407B8399F92BFEBF000000000000084050C2DE1EB8AB21C0407B8399F92BFEBF0000000000000840B0A684BA7CCC21C0407B8399F92BFEBF000000000000084048A3049220FD22C0C09683DDDAA6F4BF000000000000084090438D362AB326C0C09683DDDAA6F4BF0000000000000840509860EFAACC26C080F0E816D5DAF3BF00000000000008401079B440D10C27C080F0E816D5DAF3BF0000000000000840	\N	\N
second_floor	\N	0.25	510	510	508	t	01020000A034BF0D0002000000F05DA33F685E20C0407B8399F92BFEBF0000000000000840F05DA33F68DE20C0407B8399F92BFEBF0000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.78718059746499591	511	502	510	t	01020000A034BF0D0003000000301A9ED3BD9619C0407B8399F92BFEBF000000000000084010F3CFC030221FC0407B8399F92BFEBF0000000000000840F05DA33F685E20C0407B8399F92BFEBF0000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.760524743047258811	512	447	511	t	01020000A034BF0D0003000000F8788019788324C0D8EDB5F420A327C0000000000000084050A4B0C2940825C03019E69D3D2828C0000000000000084050A4B0C2940825C0909B9E7061F128C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.65972356744519622	513	446	512	t	01020000A034BF0D000500000070E5CB16888E29C0A0C8AB774CA125C0000000000000084020389449CFE02AC0F075E344054F24C0000000000000084020389449CFE02AC07863B274DEBE21C00000000000000840F00461169C2D2BC0A896E5A7117221C00000000000000840F00461169C2D2BC010E0328373FB20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.68677859038749034	514	512	513	t	01020000A034BF0D0002000000F00461169C2D2BC010E0328373FB20C00000000000000840F00461169C2D2BC080856023A4371FC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.33441322148874097	515	514	515	t	01020000A034BF0D00030000001865BD4E9F1129C010E0328373FB20C000000000000008409882DED5B52A28C010E0328373FB20C00000000000000840D84F6758E4EA26C0500EA35738771FC00000000000000840	\N	\N
second_floor	\N	0.249970558235915519	516	516	514	t	01020000A034BF0D00020000003091D6729B9129C010E0328373FB20C000000000000008401865BD4E9F1129C010E0328373FB20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.804692373896500612	517	512	516	t	01020000A034BF0D0003000000F00461169C2D2BC010E0328373FB20C00000000000000840288FABEB84782AC010E0328373FB20C000000000000008403091D6729B9129C010E0328373FB20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.84658593531987258	518	515	517	t	01020000A034BF0D0004000000D84F6758E4EA26C0500EA35738771FC0000000000000084048145ABFDAEA26C0500EA35738771FC000000000000008408069BC8F9B9126C0F8316F5BDB1420C00000000000000840A85F773F685E23C0F8316F5BDB1420C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	0.729643968321006531	519	515	518	t	01020000A034BF0D0003000000D84F6758E4EA26C0500EA35738771FC000000000000008409855AADD187827C0A04CBA77D45C1EC00000000000000840C81ADF741A7827C060D6707B0C011DC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.00397283970075257	520	518	519	t	01020000A034BF0D0003000000C81ADF741A7827C060D6707B0C011DC00000000000000840C00D375098E327C0103C93B3142A1CC000000000000008401084D38C95E328C040325D3A1A2A1AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.63891211182687013	521	518	520	t	01020000A034BF0D0004000000C81ADF741A7827C060D6707B0C011DC00000000000000840E0FCB6D1F14427C0809A2035BB9A1CC00000000000000840E0FCB6D1F14427C0203070B2579A17C0000000000000084028A17C8670EB26C0B078FB1B55E716C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	0.429973598563549331	522	520	521	t	01020000A034BF0D000200000028A17C8670EB26C0B078FB1B55E716C0000000000000084088AE9C064B0F26C0B078FB1B55E716C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.04999999600188687	523	521	522	t	01020000A034BF0D000300000088AE9C064B0F26C0B078FB1B55E716C0000000000000084050773460860225C0B078FB1B55E716C00000000000000840E06C256DB1F523C0B078FB1B55E716C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048ia	0.944950908845351822	524	523	524	t	01020000A034BF0D0005000000E06C256DB1F523C0F0F826E7590B13C00000000000000840E06C256DB1F523C03030B028BA7011C00000000000000840E06C256DB1F523C0502EEA7BC41F11C00000000000000840C06C256DB1F523C0102EEA7BC41F11C00000000000000840C06C256DB1F523C0606A3F6271870EC00000000000000840	\N	\N
second_floor	\N	0.0899999999996197175	525	525	523	t	01020000A034BF0D0002000000E06C256DB1F523C0A086E9DC826713C00000000000000840E06C256DB1F523C0F0F826E7590B13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	0.874825463743505338	526	522	525	t	01020000A034BF0D0003000000E06C256DB1F523C0B078FB1B55E716C00000000000000840E06C256DB1F523C0604F609B220215C00000000000000840E06C256DB1F523C0A086E9DC826713C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iX	0.953872625850570866	527	526	527	t	01020000A034BF0D000500000088E0DC5CA2C321C0F0F826E7590B13C0000000000000084088E0DC5CA2C321C03030B028BA7011C0000000000000084088E0DC5CA2C321C060F6B3ACE54011C000000000000008406090243E1DD821C0B09624EAEF1711C000000000000008406090243E1DD821C02099CA851A970EC00000000000000840	\N	\N
second_floor	\N	0.0899999999996197175	528	528	526	t	01020000A034BF0D000200000088E0DC5CA2C321C0A086E9DC826713C0000000000000084088E0DC5CA2C321C0F0F826E7590B13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.72239760869136704	529	522	528	t	01020000A034BF0D0006000000E06C256DB1F523C0B078FB1B55E716C000000000000008406064167ADCE822C0B078FB1B55E716C00000000000000840F8562C5F519E22C0B078FB1B55E716C0000000000000084088E0DC5CA2C321C0D08B5C17F73115C0000000000000084088E0DC5CA2C321C0604F609B220215C0000000000000084088E0DC5CA2C321C0A086E9DC826713C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048ix	0.945075263554304601	530	529	530	t	01020000A034BF0D000500000088AE9C064B0F26C0F0F826E7590B13C0000000000000084088AE9C064B0F26C03030B028BA7011C0000000000000084088AE9C064B0F26C020D03715E51F11C00000000000000840A0AE9C064B0F26C0F0CF3715E51F11C00000000000000840A0AE9C064B0F26C0A026A42F30870EC00000000000000840	\N	\N
second_floor	\N	0.0899999999996197175	531	531	529	t	01020000A034BF0D000200000088AE9C064B0F26C0A086E9DC826713C0000000000000084088AE9C064B0F26C0F0F826E7590B13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	0.874825463743505338	532	521	531	t	01020000A034BF0D000300000088AE9C064B0F26C0B078FB1B55E716C0000000000000084088AE9C064B0F26C0604F609B220215C0000000000000084088AE9C064B0F26C0A086E9DC826713C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048i_	0.0226459209316883375	533	532	533	t	01020000A034BF0D0002000000307CAFA8562828C050F726E7590B13C0000000000000084078DEA186893028C0C032422BF4FA12C00000000000000840	\N	\N
second_floor	\N	0.116738465468237254	534	534	532	t	01020000A034BF0D0003000000280AB6A6490728C0A086E9DC826713C00000000000000840280AB6A6490728C070DB19EB734D13C00000000000000840307CAFA8562828C050F726E7590B13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.10446169916671755	535	520	534	t	01020000A034BF0D000400000028A17C8670EB26C0B078FB1B55E716C0000000000000084030E804AD0F1C27C0A0EAEACE168616C00000000000000840280AB6A6490728C0B0A688DBA2AF14C00000000000000840280AB6A6490728C0A086E9DC826713C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048i_	1.04118803574269925	536	533	535	t	01020000A034BF0D000700000078DEA186893028C0C032422BF4FA12C0000000000000084078DEA186893028C0902EB028BA7011C0000000000000084078DEA186893028C000E1E53F5B4811C00000000000000840D0FA5B62912228C0B0195AF76A2C11C00000000000000840D0FA5B62912228C0E02249BDDC8C0EC00000000000000840700AB2397E0228C06061A11A900C0EC00000000000000840700AB2397E0228C0A0D1B7C8D7ED0DC00000000000000840	\N	\N
second_floor	\N	0.114707788248068709	603	603	601	t	01020000A034BF0D000200000076BF72FA34EA4AC0A03A7185218023C0000000000000084076BF72FA34EA4AC030FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	0.24801179887113603	537	536	537	t	01020000A034BF0D0003000000688875DFD06628C0A086E9DC826713C00000000000000840A065A92255B228C0104151638BFE13C00000000000000840688C0E9784C628C0104151638BFE13C00000000000000840	\N	\N
second_floor	\N	0.127279220613563282	538	538	536	t	01020000A034BF0D0002000000C0409464BC3828C050F726E7590B13C00000000000000840688875DFD06628C0A086E9DC826713C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048i_	0.0226459209316883375	539	533	538	t	01020000A034BF0D000200000078DEA186893028C0C032422BF4FA12C00000000000000840C0409464BC3828C050F726E7590B13C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Mn	3.95391621922730296	540	539	540	t	01020000A034BF0D000B00000024B4F1A7B3A030C058FCC28A664523C0000000000000084024B4F1A7B3A030C080F72720617622C000000000000008404C0E56E392A030C0D8ABF0961F7622C000000000000008404C0E56E392A030C01821C90BFC2822C000000000000008405CA3AC8A093630C0304B765AE95321C000000000000008405CA3AC8A093630C0908D8457D85620C000000000000008407000FB90840330C0708F42C89CE31FC000000000000008407000FB90840330C0E0D47EF7372A1CC000000000000008407000FB90840330C070C8F88AEC7018C000000000000008408C8EDE26AF0F30C000906A33424018C000000000000008408C8EDE26AF0F30C0B048466494D217C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	541	541	539	t	01020000A034BF0D000200000024B4F1A7B3A030C0A03A7185218023C0000000000000084024B4F1A7B3A030C058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144698998	542	445	541	t	01020000A034BF0D000300000024B4F1A7B3A030C058D009A2F9CC25C0000000000000084024B4F1A7B3A030C09061A28DCD9C24C0000000000000084024B4F1A7B3A030C0A03A7185218023C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Mo	3.9177370883842153	543	542	543	t	01020000A034BF0D0006000000302A3BB525F332C058FCC28A664523C00000000000000840302A3BB525F332C080F72720617622C0000000000000084010849FF004F332C040ABF0961F7622C0000000000000084010849FF004F332C0A821C90BFC2822C0000000000000084098083048866332C0B82AEABAFE0921C0000000000000084098083048866332C06036261400CD17C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	544	544	542	t	01020000A034BF0D0002000000302A3BB525F332C0A03A7185218023C00000000000000840302A3BB525F332C058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144698998	545	444	544	t	01020000A034BF0D0003000000302A3BB525F332C058D009A2F9CC25C00000000000000840302A3BB525F332C09061A28DCD9C24C00000000000000840302A3BB525F332C0A03A7185218023C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Mo	0.794829018554867983	546	543	545	t	01020000A034BF0D000300000098083048866332C06036261400CD17C00000000000000840885684B57FF232C0A0FED45E1A9115C00000000000000840885684B57FF232C0B06683A6FB8B15C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Mo	0.111689468351547194	547	543	546	t	01020000A034BF0D000200000098083048866332C06036261400CD17C00000000000000840D0CE647C4E4F32C0404FF9E4207C17C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.16324328044452718	548	439	547	t	01020000A034BF0D00040000001478CFF27D8134C038747ADF03A427C00000000000000840DC63433B30FD32C0A89C924E9FAC2AC00000000000000840DC63433B30FD32C098166E11F1B32AC00000000000000840F458A3AC7DFC32C0682CAE2E56B52AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MC	1.69813226291298269	549	548	549	t	01020000A034BF0D0004000000686D51F45E5732C0682CAE2E56B52AC00000000000000840F0D938F008C931C0682CAE2E56B52AC000000000000008401CB5326F732531C0682CAE2E56B52AC00000000000000840C4AFACCE5FCA30C01837BA6F7D6B2BC00000000000000840	\N	\N
second_floor	\N	0.0944491311510091691	550	550	548	t	01020000A034BF0D000200000048DBCAC58C6F32C0682CAE2E56B52AC00000000000000840686D51F45E5732C0682CAE2E56B52AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.550550868849015274	551	547	550	t	01020000A034BF0D0002000000F458A3AC7DFC32C0682CAE2E56B52AC0000000000000084048DBCAC58C6F32C0682CAE2E56B52AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MC	3.54203926811741532	552	549	551	t	01020000A034BF0D0007000000C4AFACCE5FCA30C01837BA6F7D6B2BC00000000000000840C4AFACCE5FCA30C0C8F3256190EA2BC00000000000000840C4AFACCE5FCA30C0B87BFA75BE1530C00000000000000840184A7CB3739830C064E12A91AA4730C00000000000000840184A7CB3739830C0D4E153D3DAFE30C0000000000000084000A8FA86D2A330C0BC3FD2A6390A31C0000000000000084000A8FA86D2A330C0C4DA1D681E2731C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MC	1.32802359982341156	553	549	552	t	01020000A034BF0D0003000000C4AFACCE5FCA30C01837BA6F7D6B2BC0000000000000084068D549BB932030C06082F448E5172AC000000000000008402014D20977792FC06082F448E5172AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MB	3.65988953173157849	554	553	554	t	01020000A034BF0D000A000000F458A3AC7DFC32C0608DBFFA29042CC00000000000000840F458A3AC7DFC32C058925A652FD32CC00000000000000840D4FE3E719EFC32C018DE91EE70D32CC00000000000000840D4FE3E719EFC32C08868B97994202DC00000000000000840D0410410800F34C080EE43B757462FC00000000000000840D0410410800F34C0A4EE972ED62930C00000000000000840208CD6DFB02F34C0F4386AFE064A30C00000000000000840208CD6DFB02F34C090437A93A7FC30C0000000000000084088D2DABDB12234C028FD75B5A60931C0000000000000084088D2DABDB12234C0E4DE5B49622631C00000000000000840	\N	\N
second_floor	\N	0.117704428251997228	555	555	553	t	01020000A034BF0D0002000000F458A3AC7DFC32C0C8AD8339E6C72BC00000000000000840F458A3AC7DFC32C0608DBFFA29042CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.536255205691020365	556	547	555	t	01020000A034BF0D0002000000F458A3AC7DFC32C0682CAE2E56B52AC00000000000000840F458A3AC7DFC32C0C8AD8339E6C72BC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6M6	3.67388455316772999	557	556	557	t	01020000A034BF0D000A000000FC6B4EE547FD38C0608DBFFA29042CC00000000000000840FC6B4EE547FD38C058925A652FD32CC000000000000008400CC6B22027FD38C038DE91EE70D32CC000000000000008400CC6B22027FD38C06868B97994202DC00000000000000840C4DF0774C6EA37C0F8340FD355452FC00000000000000840C4DF0774C6EA37C0E0917D3C552930C0000000000000084034AFC595AFC937C070C2BF1A6C4A30C0000000000000084034AFC595AFC937C014BA247742FC30C00000000000000840180A78BB91D737C0F814D79C240A31C00000000000000840180A78BB91D737C0B0C2E58C6F2931C00000000000000840	\N	\N
second_floor	\N	0.117704428251997228	558	558	556	t	01020000A034BF0D0002000000FC6B4EE547FD38C0C8AD8339E6C72BC00000000000000840FC6B4EE547FD38C0608DBFFA29042CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.07008630144699168	559	434	558	t	01020000A034BF0D0003000000FC6B4EE547FD38C038747ADF03A427C00000000000000840FC6B4EE547FD38C0D88652313AAB2AC00000000000000840FC6B4EE547FD38C0C8AD8339E6C72BC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6M5	3.67268547063345041	560	559	560	t	01020000A034BF0D000A000000309F81187B303AC0608DBFFA29042CC00000000000000840309F81187B303AC050925A652FD32CC0000000000000084004451DDD9B303AC0F8DD91EE70D32CC0000000000000084004451DDD9B303AC0A868B97994202DC000000000000008402C2BC889FC423BC0F8340FD355452FC000000000000008402C2BC889FC423BC0AC8F3A933E2130C000000000000008409C68D260A0633BC01CCD446AE24130C000000000000008409C68D260A0633BC04407D6ABDEFC30C000000000000008400C429E7125563BC0D42D0A9B590A31C000000000000008400C429E7125563BC07C819F5D7B2931C00000000000000840	\N	\N
second_floor	\N	0.117704428251997228	561	561	559	t	01020000A034BF0D0002000000309F81187B303AC0C8AD8339E6C72BC00000000000000840309F81187B303AC0608DBFFA29042CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.07008630144699168	562	429	561	t	01020000A034BF0D0003000000309F81187B303AC038747ADF03A427C00000000000000840309F81187B303AC0D88652313AAB2AC00000000000000840309F81187B303AC0C8AD8339E6C72BC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6M0	5.76126341087317506	563	562	563	t	01020000A034BF0D000B0000004856D4771B3C3DC0D842A7C82A9F2AC00000000000000840C0E9EC7B71CA3DC0D842A7C82A9F2AC0000000000000084020D7F92095D33DC0D842A7C82A9F2AC0000000000000084074B87435431B3EC02880B19FCE0F2AC00000000000000840BCFA29CD535C3EC02880B19FCE0F2AC0000000000000084064C9F15F461D3FC0781D41C5B3912BC0000000000000084064C9F15F461D3FC0B4EC7AF7C22030C00000000000000840F48BE788A2FC3EC0242A85CE664130C00000000000000840F48BE788A2FC3EC03CAA95475AFD30C00000000000000840DC7961E1080A3FC024980FA0C00A31C00000000000000840DC7961E1080A3FC0CCEBA462E22931C00000000000000840	\N	\N
second_floor	\N	0.0990523598810000294	564	564	562	t	01020000A034BF0D0002000000780EFEF8BF223DC0D842A7C82A9F2AC000000000000008404856D4771B3C3DC0D842A7C82A9F2AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.68748455667194364	565	428	564	t	01020000A034BF0D0004000000AC71F9CBCE103BC038747ADF03A427C0000000000000084000D98F40628E3CC0D842A7C82A9F2AC00000000000000840007BE5F469943CC0D842A7C82A9F2AC00000000000000840780EFEF8BF223DC0D842A7C82A9F2AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6M_	3.95726694323858164	566	565	566	t	01020000A034BF0D000A000000F45BF6C287593BC058FCC28A664523C00000000000000840F45BF6C287593BC068F72720617622C0000000000000084094019287A8593BC028ACF0961F7622C0000000000000084094019287A8593BC0A820C90BFC2822C00000000000000840B45C0C5092D73BC0606AD47A282D21C00000000000000840B45C0C5092D73BC0D8253B53C13020C00000000000000840249A162736F83BC0F0554D4AF3DE1FC00000000000000840249A162736F83BC0B0D96A2B337818C0000000000000084094A7D685D1EA3BC0700F6BA6A04218C0000000000000084094A7D685D1EA3BC090E27A6BA9D317C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	567	567	565	t	01020000A034BF0D0002000000F45BF6C287593BC0A03A7185218023C00000000000000840F45BF6C287593BC058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.78601396263049139	568	427	567	t	01020000A034BF0D0003000000F45BF6C287593BC0A89F80F1911227C00000000000000840F45BF6C287593BC09061A28DCD9C24C00000000000000840F45BF6C287593BC0A03A7185218023C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MV	1.99243655854302282	569	568	569	t	01020000A034BF0D0004000000A28CEF4DD9CA40C0D0BB70247F5128C00000000000000840A28CEF4DD9CA40C0C0E2A12C2B6E29C00000000000000840A28CEF4DD9CA40C038B299800ED429C00000000000000840720A1B4CD93A41C078A947790E942BC00000000000000840	\N	\N
second_floor	\N	0.108744794309004078	570	570	568	t	01020000A034BF0D0002000000A28CEF4DD9CA40C01866A2BED11928C00000000000000840A28CEF4DD9CA40C0D0BB70247F5128C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144700419	571	422	570	t	01020000A034BF0D0003000000A28CEF4DD9CA40C058D009A2F9CC25C00000000000000840A28CEF4DD9CA40C0283F71B625FD26C00000000000000840A28CEF4DD9CA40C01866A2BED11928C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MV	3.4454310311275278	572	569	571	t	01020000A034BF0D0006000000720A1B4CD93A41C078A947790E942BC00000000000000840720A1B4CD93A41C0509291EF562C30C000000000000008402A29A0372B4B41C0C0CF9BC6FA4C30C000000000000008402A29A0372B4B41C0E8ED011B56FC30C00000000000000840E8F91B995E4441C06C4C0A58EF0931C00000000000000840E8F91B995E4441C0D81530EDE72831C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MQ	5.66938160823340276	573	572	573	t	01020000A034BF0D000B000000A46DE562C63742C02893DB4C143F2AC0000000000000084060B7F164F17E42C02893DB4C143F2AC00000000000000840CCC97425BCA042C02893DB4C143F2AC00000000000000840A2763AE9F3A942C0C8DFC43D351A2AC00000000000000840A69B727477CA42C0C8DFC43D351A2AC0000000000000084096BD8BFFAB2843C08867296A07932BC0000000000000084096BD8BFFAB2843C058710268D32B30C00000000000000840DE9E06145A1843C0C8AE0C3F774C30C00000000000000840DE9E06145A1843C0E00E91A2D9FC30C00000000000000840DA795919FE1E43C0D8C436AD210A31C00000000000000840DA795919FE1E43C0D0F470F0612A31C00000000000000840	\N	\N
second_floor	\N	0.0900000000000034106	574	574	572	t	01020000A034BF0D0002000000B81B2D44412C42C02893DB4C143F2AC00000000000000840A46DE562C63742C02893DB4C143F2AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MV	2.22149827801891142	575	569	574	t	01020000A034BF0D0006000000720A1B4CD93A41C078A947790E942BC00000000000000840DEBCFB9A4F9941C0C8DFC43D351A2AC00000000000000840BA12D8BD13BA41C0C8DFC43D351A2AC0000000000000084090BF9D814BC341C02893DB4C143F2AC00000000000000840FCD1204216E541C02893DB4C143F2AC00000000000000840B81B2D44412C42C02893DB4C143F2AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MP	5.74862458177883262	576	575	576	t	01020000A034BF0D000B00000050B5C6DDDAC545C01097699D8F9B2AC00000000000000840966BBADBAF7E45C01097699D8F9B2AC00000000000000840EEFCA758EF7345C01097699D8F9B2AC00000000000000840B63D180CA35345C0389A2A6B5E1A2AC0000000000000084012E30B9CC43245C0389A2A6B5E1A2AC000000000000008408E4AB6CEC7D444C048FC80A051922BC000000000000008408E4AB6CEC7D444C020F693B0A12B30C0000000000000084046693BBA19E544C090339E87454C30C0000000000000084046693BBA19E544C030CED4B45DFD30C000000000000008402AE29E425CDE44C068DC0DA4D80A31C000000000000008402AE29E425CDE44C0B082D8B9EF2A31C00000000000000840	\N	\N
second_floor	\N	0.0900000000000034106	577	577	575	t	01020000A034BF0D00020000003C077FFC5FD145C01097699D8F9B2AC0000000000000084050B5C6DDDAC545C01097699D8F9B2AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.70214075262370335	578	405	577	t	01020000A034BF0D000400000046C63E9D2FDE46C0C836700860B327C00000000000000840326E00B8232446C01097699D8F9B2AC00000000000000840F6508BFE8A1846C01097699D8F9B2AC000000000000008403C077FFC5FD145C01097699D8F9B2AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MK	3.64089571896671815	579	578	579	t	01020000A034BF0D000A000000EADD226D9D4B47C0C8AB17E570162CC00000000000000840EADD226D9D4B47C0D0B0B24F76E52CC00000000000000840220BD50A8D4B47C0E8FBE9D8B7E52CC00000000000000840220BD50A8D4B47C0A0871164DB322DC00000000000000840CA548D7238C246C0086130C52D582FC00000000000000840CA548D7238C246C0843098E2162C30C0000000000000084012360887E6B146C0F46DA2B9BA4C30C0000000000000084012360887E6B146C0CC93D082E8FC30C0000000000000084032B942B399B846C00C9A45DB4E0A31C0000000000000084032B942B399B846C0544010F1652A31C00000000000000840	\N	\N
second_floor	\N	0.0934017198709966578	580	580	578	t	01020000A034BF0D0002000000EADD226D9D4B47C0E8326F8B9EE62BC00000000000000840EADD226D9D4B47C0C8AB17E570162CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.10008630144699282	581	404	580	t	01020000A034BF0D0003000000EADD226D9D4B47C0C836700860B327C00000000000000840EADD226D9D4B47C0F80B3E83F2C92AC00000000000000840EADD226D9D4B47C0E8326F8B9EE62BC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MJ	3.64240924473739858	582	581	582	t	01020000A034BF0D000A0000008277BC0637E547C0C8AB17E570162CC000000000000008408277BC0637E547C0C8B0B24F76E52CC00000000000000840A24A0A6947E547C050FDE9D8B7E52CC00000000000000840A24A0A6947E547C030861164DB322DC00000000000000840F6FDCC43626E48C078531CCF46572FC00000000000000840F6FDCC43626E48C01C8D9326C92B30C00000000000000840AE1C522FB47E48C08CCA9DFD6C4C30C00000000000000840AE1C522FB47E48C044244A2B85FD30C00000000000000840B60B1BDCF57748C03446B8D1010B31C00000000000000840B60B1BDCF57748C0CC6213BAEF2A31C00000000000000840	\N	\N
second_floor	\N	0.0934017198709966578	583	583	581	t	01020000A034BF0D00020000008277BC0637E547C0E8326F8B9EE62BC000000000000008408277BC0637E547C0C8AB17E570162CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.10008630144699282	584	399	583	t	01020000A034BF0D00030000008277BC0637E547C0C836700860B327C000000000000008408277BC0637E547C0F80B3E83F2C92AC000000000000008408277BC0637E547C0E8326F8B9EE62BC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6LL	3.96223703471859023	585	584	585	t	01020000A034BF0D000A000000FA74D8DA927948C058FCC28A664523C00000000000000840FA74D8DA927948C058F72720617622C00000000000000840EA47263DA37948C090ABF0961F7622C00000000000000840EA47263DA37948C03021C90BFC2822C00000000000000840C6E8C20A97B848C0C89D56D52C2D21C00000000000000840C6E8C20A97B848C0B84686E1B53120C00000000000000840820748F6E8C848C09097E366DCE01FC00000000000000840820748F6E8C848C030D088741F7A18C00000000000000840FE5F79CA37C248C010941316964418C00000000000000840FE5F79CA37C248C01072AF248BCE17C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	586	586	584	t	01020000A034BF0D0002000000FA74D8DA927948C0A03A7185218023C00000000000000840FA74D8DA927948C058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.10008630144700703	587	398	586	t	01020000A034BF0D0003000000FA74D8DA927948C0C836700860B327C00000000000000840FA74D8DA927948C09061A28DCD9C24C00000000000000840FA74D8DA927948C0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.09845406209645358	588	397	587	t	01020000A034BF0D00020000006AA776C5A31E4AC0C836700860B327C000000000000008402A89E0F291DC4AC0D0BD17BE18AB2AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Nk	0.431801161535688593	589	588	589	t	01020000A034BF0D00030000001A4A73B5BFE44AC0C8AB17E570162CC000000000000008401A4A73B5BFE44AC0101D24A83FF12CC00000000000000840BEA46EA426E54AC0A0871164DBF22CC00000000000000840	\N	\N
second_floor	\N	0.0934017198709966578	590	590	588	t	01020000A034BF0D00020000001A4A73B5BFE44AC0E8326F8B9EE62BC000000000000008401A4A73B5BFE44AC0C8AB17E570162CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.642721995200796981	591	587	590	t	01020000A034BF0D00030000002A89E0F291DC4AC0D0BD17BE18AB2AC000000000000008401A4A73B5BFE44AC088C162C8CFCB2AC000000000000008401A4A73B5BFE44AC0E8326F8B9EE62BC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Nk	3.21016691692983347	592	589	591	t	01020000A034BF0D0008000000BEA46EA426E54AC0A0871164DBF22CC00000000000000840BEA46EA426E54AC0B8871164DB322DC000000000000008403208A4E7D25B4AC0E8F93B572A582FC000000000000008403208A4E7D25B4AC05460A3EA3A2C30C000000000000008407AE91EFC804B4AC0C49DADC1DE4C30C000000000000008407AE91EFC804B4AC00C513A6713FD30C00000000000000840C2E2BE4C33524AC09C437A08780A31C00000000000000840C2E2BE4C33524AC03460D5F0652A31C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Nk	0.0191456334580311534	593	589	592	t	01020000A034BF0D0003000000BEA46EA426E54AC0A0871164DBF22CC000000000000008403A96D315CBE64AC0B8C17D9E49EC2CC00000000000000840BA3B6FDAEBE64AC0B8C17D9E49EC2CC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Ng	1.71837064130224659	594	593	594	t	01020000A034BF0D0004000000A26DE562C6374BC0D0BD17BE18AB2AC000000000000008405AB7F164F17E4BC0D0BD17BE18AB2AC000000000000008407A8B80D1D8CA4BC0D0BD17BE18AB2AC00000000000000840762D136861FE4BC0C84562183B792BC00000000000000840	\N	\N
second_floor	\N	0.0962825636510160621	595	595	593	t	01020000A034BF0D000200000072663666732B4BC0D0BD17BE18AB2AC00000000000000840A26DE562C6374BC0D0BD17BE18AB2AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.61625520413014101	596	587	595	t	01020000A034BF0D00030000002A89E0F291DC4AC0D0BD17BE18AB2AC00000000000000840BA1C2A6448E44AC0D0BD17BE18AB2AC0000000000000084072663666732B4BC0D0BD17BE18AB2AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Ng	3.51831646826663524	597	594	596	t	01020000A034BF0D0007000000762D136861FE4BC0C84562183B792BC00000000000000840762D136861FE4BC030127E4BD7FC2BC00000000000000840762D136861FE4BC0F8CB9704C01830C000000000000008400AA44F8178154CC020B91037EE4630C000000000000008400AA44F8178154CC034BCE4E7580331C000000000000008405AFB95758F114CC0940D58FF2A0B31C000000000000008405AFB95758F114CC0B4B650BAEF2A31C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Ng	1.25591647231050341	598	594	597	t	01020000A034BF0D0003000000762D136861FE4BC0C84562183B792BC000000000000008406AA98D355A544CC0F05578E257212AC00000000000000840AA55D6EE867B4CC0F05578E257212AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6LM	3.9843687642332446	599	598	599	t	01020000A034BF0D00090000002230B0040C4E4AC058FCC28A664523C000000000000008402230B0040C4E4AC068D59182BA2822C000000000000008402230B0040C4E4AC018955C24001F22C00000000000000840964B9AF18B114AC0E80205D8FF2C21C00000000000000840964B9AF18B114AC0D8AB34E4883120C00000000000000840DE2C15063A014AC0F061406C82E01FC00000000000000840DE2C15063A014AC0D0052C6F797A18C000000000000008409A8F1D7EF9074AC0F0EFE8AE7D4418C000000000000008409A8F1D7EF9074AC0303E9B6BBAAF17C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	600	600	598	t	01020000A034BF0D00020000002230B0040C4E4AC0A03A7185218023C000000000000008402230B0040C4E4AC058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.72971743634536779	601	396	600	t	01020000A034BF0D00030000002230B0040C4E4AC0E0138A0BBFF526C000000000000008402230B0040C4E4AC09061A28DCD9C24C000000000000008402230B0040C4E4AC0A03A7185218023C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6LR	3.95334153263834187	602	601	602	t	01020000A034BF0D000600000076BF72FA34EA4AC030FCC28A664523C0000000000000084076BF72FA34EA4AC050F72720617622C000000000000008408292C05C45EA4AC020ABF0961F7622C000000000000008408292C05C45EA4AC07021C90BFC2822C000000000000008401EEC2CE1E2314BC000BB17FA850A21C000000000000008401EEC2CE1E2314BC020EE8F8B1AA817C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.17008630144700021	604	395	603	t	01020000A034BF0D000300000076BF72FA34EA4AC068A7AD1237D725C0000000000000084076BF72FA34EA4AC09061A28DCD9C24C0000000000000084076BF72FA34EA4AC0A03A7185218023C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6LS	3.9861568793049007	605	604	605	t	01020000A034BF0D000B000000F6B180612A134CC058FCC28A664523C00000000000000840F6B180612A134CC050F72720617622C00000000000000840FE84CEC33A134CC030ABF0961F7622C00000000000000840FE84CEC33A134CC08821C90BFC2822C00000000000000840AAF902A295484CC0D84EF792905321C00000000000000840AAF902A295484CC018FCB31F715820C0000000000000084036DD9DC291614CC0D0DB903A01E91FC0000000000000084036DD9DC291614CC00015E8FE66611AC0000000000000084036DD9DC291614CC0D0C63FE94A7318C0000000000000084082157E5AD05B4CC0308941A83F4518C0000000000000084082157E5AD05B4CC030A5A91DDBAF17C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	606	606	604	t	01020000A034BF0D0002000000F6B180612A134CC0A03A7185218023C00000000000000840F6B180612A134CC058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.17008630144700021	607	394	606	t	01020000A034BF0D0003000000F6B180612A134CC068A7AD1237D725C00000000000000840F6B180612A134CC09061A28DCD9C24C00000000000000840F6B180612A134CC0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lE	1.03168724842709159	608	314	607	t	01020000A034BF0D0003000000D24212692D984DC0880F09DE84662AC0000000000000084012BF4DABE0564DC08800F7E6516129C00000000000000840729D11BACC3A4DC0087A062202F128C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lE	2.45202655902118671	609	313	608	t	01020000A034BF0D0006000000D24212692D984DC070E450AF8FAB2AC000000000000008408E0842B888974DC080CD917222AE2AC000000000000008408E0842B888974DC0686545C1E0E32BC000000000000008408E0842B888974DC0B8169694658F2CC000000000000008408E0842B888974DC0A09878F413172DC000000000000008408E0842B888974DC078166ED7EE912FC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lE	0.700130196159255425	610	608	609	t	01020000A034BF0D00020000008E0842B888974DC078166ED7EE912FC000000000000008400A67A82029584DC0B0DD0EA2B14730C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lE	0.749438712518126215	611	608	610	t	01020000A034BF0D00020000008E0842B888974DC078166ED7EE912FC0000000000000084022E5763D5CDB4DC0FC31A1C8A35030C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.71181754123300323	612	611	448	t	01020000A034BF0D0002000000005EA33F689E22C0108FFE4D940F2DC00000000000000840005EA33F689E22C0D8EDB5F420A327C00000000000000840	\N	\N
second_floor	\N	3.88723068316779363	613	612	611	t	01020000A034BF0D0003000000F87D8A907CF124C05807A30C40F631C00000000000000840005EA33F689E22C08048698C39D92DC00000000000000840005EA33F689E22C0108FFE4D940F2DC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.77678287975999183	614	613	329	t	01020000A034BF0D00020000003B548F320E5451C088FDF44BA63D2DC000000000000008403B548F320E5451C0A8AAA3CFEFAF27C00000000000000840	\N	\N
second_floor	\N	3.69828326745999147	615	614	613	t	01020000A034BF0D000300000089855B35799E51C044E93BEB08DE31C000000000000008403B548F320E5451C07823582DC9962DC000000000000008403B548F320E5451C088FDF44BA63D2DC00000000000000840	\N	\N
first_floor	\N	3.63916967176426942	616	309	612	f	01020000A034BF0D0002000000F87D8A907CF124C05807A30C40F631C09A9999999999E93FF87D8A907CF124C05807A30C40F631C00000000000000840	\N	\N
first_floor	\N	3.50436618393977728	617	311	614	f	01020000A034BF0D000200000089855B35799E51C044E93BEB08DE31C09A9999999999E93F89855B35799E51C044E93BEB08DE31C00000000000000840	\N	\N
first_floor	\N	0.604338199065438175	618	172	336	t	01020000A034BF0D00020000007FDC7F2D95B752C0F8BDA57F49EC2AC09A9999999999E93F83DC7F2D95B752C090BCA57F49EC2AC00000000000000840	\N	\N
\.


--
-- Data for Name: edges_vertices_pgr; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.edges_vertices_pgr (id, cnt, chk, ein, eout, the_geom) FROM stdin;
1	\N	\N	\N	\N	01010000A034BF0D00CCC6C444F70B3FC0283B51E7C38123C09A9999999999E93F
2	\N	\N	\N	\N	01010000A034BF0D00C4C1243DDC6F3EC0286CC2FEA5D625C09A9999999999E93F
3	\N	\N	\N	\N	01010000A034BF0D00CCC6C444F70B3FC0680F4036204A23C09A9999999999E93F
4	\N	\N	\N	\N	01010000A034BF0D0000714B1FBF8C3FC0807E2ADAF67913C09A9999999999E93F
5	\N	\N	\N	\N	01010000A034BF0D009C983119DFF43BC0386CC2FEA5D625C09A9999999999E93F
6	\N	\N	\N	\N	01010000A034BF0D009C939111C4583BC0680F4036204A23C09A9999999999E93F
7	\N	\N	\N	\N	01010000A034BF0D002C812E8413EB3BC0307C1B72A1D217C09A9999999999E93F
8	\N	\N	\N	\N	01010000A034BF0D009C939111C4583BC0583B51E7C38123C09A9999999999E93F
9	\N	\N	\N	\N	01010000A034BF0D006465FEE5ABC13AC0486CC2FEA5D625C09A9999999999E93F
10	\N	\N	\N	\N	01010000A034BF0D0068605EDE90253AC0F80D4036204A23C09A9999999999E93F
11	\N	\N	\N	\N	01010000A034BF0D00B02CD7C7B79639C05092C401C8C417C09A9999999999E93F
12	\N	\N	\N	\N	01010000A034BF0D0068605EDE90253AC0683B51E7C38123C09A9999999999E93F
13	\N	\N	\N	\N	01010000A034BF0D0068B4326F73253AC0486CC2FEA5D625C09A9999999999E93F
14	\N	\N	\N	\N	01010000A034BF0D004458A3AC7DFC38C0506CC2FEA5D625C09A9999999999E93F
15	\N	\N	\N	\N	01010000A034BF0D0084CBBC85C67038C0506CC2FEA5D625C09A9999999999E93F
16	\N	\N	\N	\N	01010000A034BF0D0094C61C7EABD437C0680F4036204A23C09A9999999999E93F
17	\N	\N	\N	\N	01010000A034BF0D0040084BD4A04237C080C0EE4E8ED117C09A9999999999E93F
18	\N	\N	\N	\N	01010000A034BF0D0094C61C7EABD437C0883B51E7C38123C09A9999999999E93F
19	\N	\N	\N	\N	01010000A034BF0D004498895293BD35C0606CC2FEA5D625C09A9999999999E93F
20	\N	\N	\N	\N	01010000A034BF0D005C93E94A782135C0680F4036204A23C09A9999999999E93F
21	\N	\N	\N	\N	01010000A034BF0D0088139A62CA7B33C0A0767CC5F1281CC09A9999999999E93F
22	\N	\N	\N	\N	01010000A034BF0D005C93E94A782135C0A83B51E7C38123C09A9999999999E93F
23	\N	\N	\N	\N	01010000A034BF0D0088AC901499AF33C060A1B065BEF31BC09A9999999999E93F
24	\N	\N	\N	\N	01010000A034BF0D00A4A8C7233CD733C090F98D16EB2A1CC09A9999999999E93F
25	\N	\N	\N	\N	01010000A034BF0D00E0F5E5E5601D34C010E4096880371AC09A9999999999E93F
26	\N	\N	\N	\N	01010000A034BF0D00D0CE647C4E4F32C0C063A72C027717C09A9999999999E93F
27	\N	\N	\N	\N	01010000A034BF0D00C043F5649C0133C0786CC2FEA5D625C09A9999999999E93F
28	\N	\N	\N	\N	01010000A034BF0D00082570794AC931C0786CC2FEA5D625C09A9999999999E93F
29	\N	\N	\N	\N	01010000A034BF0D0000B991AFCE3C31C0806CC2FEA5D625C09A9999999999E93F
30	\N	\N	\N	\N	01010000A034BF0D0024B4F1A7B3A030C0680F4036204A23C09A9999999999E93F
31	\N	\N	\N	\N	01010000A034BF0D001C51D44F0B0F30C0F0521D0805D017C09A9999999999E93F
32	\N	\N	\N	\N	01010000A034BF0D0024B4F1A7B3A030C0E03B51E7C38123C09A9999999999E93F
33	\N	\N	\N	\N	01010000A034BF0D0088D2CCD1059329C080B5B562C69525C09A9999999999E93F
34	\N	\N	\N	\N	01010000A034BF0D00609E71E1904427C080B5B562C69525C09A9999999999E93F
35	\N	\N	\N	\N	01010000A034BF0D00B08896D3608224C0184F4FFC5FAF27C09A9999999999E93F
36	\N	\N	\N	\N	01010000A034BF0D00107B24C261CF1BC0184F4FFC5FAF27C09A9999999999E93F
37	\N	\N	\N	\N	01010000A034BF0D00B0AB285BDEA319C0407B8399F92BFEBF9A9999999999E93F
38	\N	\N	\N	\N	01010000A034BF0D00B0AB285BDEA319C0C0DB85ACAD86FDBF9A9999999999E93F
39	\N	\N	\N	\N	01010000A034BF0D00B0AB285BDEA319C0C0CCCCCCCCCCFCBF9A9999999999E93F
40	\N	\N	\N	\N	01010000A034BF0D006079F527AB7011C0C0DB85ACAD86FDBF9A9999999999E93F
41	\N	\N	\N	\N	01010000A034BF0D0000C3E64694CDF4BF80D1E64694CDF4BF9A9999999999E93F
42	\N	\N	\N	\N	01010000A034BF0D008078F527AB7012C0C0DB85ACAD86FDBF9A9999999999E93F
43	\N	\N	\N	\N	01010000A034BF0D00F05DA33F68DE20C0407B8399F92BFEBF9A9999999999E93F
44	\N	\N	\N	\N	01010000A034BF0D001079B440D10C27C080F0E816D5DAF3BF9A9999999999E93F
45	\N	\N	\N	\N	01010000A034BF0D0070EF2DC7886B20C0407B8399F92BFEBF9A9999999999E93F
46	\N	\N	\N	\N	01010000A034BF0D0080B4213EB5C014C0681D93A2EBB927C09A9999999999E93F
47	\N	\N	\N	\N	01010000A034BF0D00000FDD6C5825E93F28897F828FFD20C09A9999999999E93F
48	\N	\N	\N	\N	01010000A034BF0D000010C12DEE49CFBF28897F828FFD20C09A9999999999E93F
49	\N	\N	\N	\N	01010000A034BF0D0040BDD35CC1B5F7BFE8968166ED1A20C09A9999999999E93F
50	\N	\N	\N	\N	01010000A034BF0D000000A10A9780793F28897F828FFD20C09A9999999999E93F
51	\N	\N	\N	\N	01010000A034BF0D0080235D8414FB08C0E8968166ED1A20C09A9999999999E93F
52	\N	\N	\N	\N	01010000A034BF0D0080F5B51E2CD5F0BFE088E89125971DC09A9999999999E93F
53	\N	\N	\N	\N	01010000A034BF0D0000172739EF64F5BF4034A69E5BEE16C09A9999999999E93F
54	\N	\N	\N	\N	01010000A034BF0D00C08C2C52A73CFCBF4034A69E5BEE16C09A9999999999E93F
55	\N	\N	\N	\N	01010000A034BF0D00004DF30EBA8406C04034A69E5BEE16C09A9999999999E93F
56	\N	\N	\N	\N	01010000A034BF0D008060E6C8A14C0FC0208876BC630013C09A9999999999E93F
57	\N	\N	\N	\N	01010000A034BF0D0040A9C743B6FA0EC080A98C83D4800EC09A9999999999E93F
58	\N	\N	\N	\N	01010000A034BF0D008060E6C8A14C0FC0301739B28C5C13C09A9999999999E93F
59	\N	\N	\N	\N	01010000A034BF0D00004DF30EBA8406C0208876BC630013C09A9999999999E93F
60	\N	\N	\N	\N	01010000A034BF0D00804EF30EBA8406C0C05495B43E710EC09A9999999999E93F
61	\N	\N	\N	\N	01010000A034BF0D00004DF30EBA8406C0301739B28C5C13C09A9999999999E93F
62	\N	\N	\N	\N	01010000A034BF0D00C08C2C52A73CFCBF208876BC630013C09A9999999999E93F
63	\N	\N	\N	\N	01010000A034BF0D00008E2C52A73CFCBFC05495B43E710EC09A9999999999E93F
64	\N	\N	\N	\N	01010000A034BF0D00C08C2C52A73CFCBF301739B28C5C13C09A9999999999E93F
65	\N	\N	\N	\N	01010000A034BF0D0000B15DBEEEBAE8BF301739B28C5C13C09A9999999999E93F
66	\N	\N	\N	\N	01010000A034BF0D000092B9B7F7D5E7BF80CB21856B3C13C09A9999999999E93F
67	\N	\N	\N	\N	01010000A034BF0D000092B9B7F7D5E7BF208876BC630013C09A9999999999E93F
68	\N	\N	\N	\N	01010000A034BF0D00007834CCA51DE7BF0078C184C2610EC09A9999999999E93F
69	\N	\N	\N	\N	01010000A034BF0D008034FF4EEED4E6BF301739B28C5C13C09A9999999999E93F
70	\N	\N	\N	\N	01010000A034BF0D00002DA4B8CFD2DBBFB0D5E8FACB1914C09A9999999999E93F
71	\N	\N	\N	\N	01010000A034BF0D008003FADFAE0FE6BFF04B3A66D0231CC09A9999999999E93F
72	\N	\N	\N	\N	01010000A034BF0D00000FDD6C5825E93F80CE57DF82481FC09A9999999999E93F
73	\N	\N	\N	\N	01010000A034BF0D0080B4213EB5C014C0409C1657F7752CC09A9999999999E93F
74	\N	\N	\N	\N	01010000A034BF0D00400781AB8F8B19C0FC189D930EA931C09A9999999999E93F
75	\N	\N	\N	\N	01010000A034BF0D0080B4213EB5C014C060D06649BB5E2CC09A9999999999E93F
76	\N	\N	\N	\N	01010000A034BF0D00400781AB8F8B19C0EC12A61DAB9433C09A9999999999E93F
77	\N	\N	\N	\N	01010000A034BF0D00400781AB8F8B19C0F0130479B94E35C09A9999999999E93F
78	\N	\N	\N	\N	01010000A034BF0D00404EBBD74E5A11C060E0DABC1EB735C09A9999999999E93F
79	\N	\N	\N	\N	01010000A034BF0D00001E7E3B0B74F4BF501707100D4036C09A9999999999E93F
80	\N	\N	\N	\N	01010000A034BF0D006050BBD74E5A12C060E0DABC1EB735C09A9999999999E93F
81	\N	\N	\N	\N	01010000A034BF0D00F05DA33F68DE20C09CD0749DE5AC35C09A9999999999E93F
82	\N	\N	\N	\N	01010000A034BF0D00308A991BCBF222C0A483A722F33E36C09A9999999999E93F
83	\N	\N	\N	\N	01010000A034BF0D00105FA33F685E20C09CD0749DE5AC35C09A9999999999E93F
84	\N	\N	\N	\N	01010000A034BF0D00F8CABD00F0FD26C0244846A9593E36C09A9999999999E93F
85	\N	\N	\N	\N	01010000A034BF0D0078B7711D6F3B21C0FC6CBB21A11A37C09A9999999999E93F
86	\N	\N	\N	\N	01010000A034BF0D00F05DA33F68DE20C0EC12A61DAB9433C09A9999999999E93F
87	\N	\N	\N	\N	01010000A034BF0D00D84014EA1F7127C054B90F6DE02934C09A9999999999E93F
88	\N	\N	\N	\N	01010000A034BF0D00105FA33F685E20C0EC12A61DAB9433C09A9999999999E93F
89	\N	\N	\N	\N	01010000A034BF0D00404EBBD74E5A11C0FC189D930EA931C09A9999999999E93F
90	\N	\N	\N	\N	01010000A034BF0D0040C6E66CB0FC02C084FF40F42A0533C09A9999999999E93F
91	\N	\N	\N	\N	01010000A034BF0D006050BBD74E5A12C0FC189D930EA931C09A9999999999E93F
92	\N	\N	\N	\N	01010000A034BF0D00808B683C3A23F1BF64CF6C460A3034C09A9999999999E93F
93	\N	\N	\N	\N	01010000A034BF0D004094A3A68EC6F4BF8433AFAC16F731C09A9999999999E93F
94	\N	\N	\N	\N	01010000A034BF0D00000E219E8222D2BFFC302EA7991931C09A9999999999E93F
95	\N	\N	\N	\N	01010000A034BF0D00802FA1F870ABE8BF747473F0CD5C32C09A9999999999E93F
96	\N	\N	\N	\N	01010000A034BF0D0078D5128EF50D25C018CFFEE9276E29C09A9999999999E93F
97	\N	\N	\N	\N	01010000A034BF0D0010DF512003302BC010E0328373FB20C09A9999999999E93F
98	\N	\N	\N	\N	01010000A034BF0D0010DF512003302BC02008B22A6B5D1FC09A9999999999E93F
99	\N	\N	\N	\N	01010000A034BF0D00406DC0E3AC1129C010E0328373FB20C09A9999999999E93F
100	\N	\N	\N	\N	01010000A034BF0D00906BECE3AC9126C0F8316F5BDB1420C09A9999999999E93F
101	\N	\N	\N	\N	01010000A034BF0D007045B886699629C010E0328373FB20C09A9999999999E93F
102	\N	\N	\N	\N	01010000A034BF0D00686694701B7827C0906DDB720E011DC09A9999999999E93F
103	\N	\N	\N	\N	01010000A034BF0D001084D38C95E328C040325D3A1A2A1AC09A9999999999E93F
104	\N	\N	\N	\N	01010000A034BF0D0028A17C8670EB26C0B078FB1B55E716C09A9999999999E93F
105	\N	\N	\N	\N	01010000A034BF0D0088AE9C064B0F26C0B078FB1B55E716C09A9999999999E93F
106	\N	\N	\N	\N	01010000A034BF0D00E06C256DB1F523C0B078FB1B55E716C09A9999999999E93F
107	\N	\N	\N	\N	01010000A034BF0D00E06C256DB1F523C0F0F826E7590B13C09A9999999999E93F
108	\N	\N	\N	\N	01010000A034BF0D00C06C256DB1F523C0606A3F6271870EC09A9999999999E93F
109	\N	\N	\N	\N	01010000A034BF0D00E06C256DB1F523C0A086E9DC826713C09A9999999999E93F
110	\N	\N	\N	\N	01010000A034BF0D0088E0DC5CA2C321C0F0F826E7590B13C09A9999999999E93F
111	\N	\N	\N	\N	01010000A034BF0D006090243E1DD821C02099CA851A970EC09A9999999999E93F
112	\N	\N	\N	\N	01010000A034BF0D0088E0DC5CA2C321C0A086E9DC826713C09A9999999999E93F
113	\N	\N	\N	\N	01010000A034BF0D0088AE9C064B0F26C0F0F826E7590B13C09A9999999999E93F
114	\N	\N	\N	\N	01010000A034BF0D00A0AE9C064B0F26C0A026A42F30870EC09A9999999999E93F
115	\N	\N	\N	\N	01010000A034BF0D0088AE9C064B0F26C0A086E9DC826713C09A9999999999E93F
116	\N	\N	\N	\N	01010000A034BF0D00307CAFA8562828C050F726E7590B13C09A9999999999E93F
117	\N	\N	\N	\N	01010000A034BF0D0078DEA186893028C0C032422BF4FA12C09A9999999999E93F
118	\N	\N	\N	\N	01010000A034BF0D00280AB6A6490728C0A086E9DC826713C09A9999999999E93F
119	\N	\N	\N	\N	01010000A034BF0D00688875DFD06628C0A086E9DC826713C09A9999999999E93F
120	\N	\N	\N	\N	01010000A034BF0D00688C0E9784C628C0104151638BFE13C09A9999999999E93F
121	\N	\N	\N	\N	01010000A034BF0D00C0409464BC3828C050F726E7590B13C09A9999999999E93F
122	\N	\N	\N	\N	01010000A034BF0D00700AB2397E0228C0A0D1B7C8D7ED0DC09A9999999999E93F
123	\N	\N	\N	\N	01010000A034BF0D00A85F773F685E23C0F8316F5BDB1420C09A9999999999E93F
124	\N	\N	\N	\N	01010000A034BF0D00082570794AC931C068550ABE186B28C09A9999999999E93F
125	\N	\N	\N	\N	01010000A034BF0D005472A2F7BBC930C0D0553F5BCF832BC09A9999999999E93F
126	\N	\N	\N	\N	01010000A034BF0D00082570794AC931C0289D3316882B28C09A9999999999E93F
127	\N	\N	\N	\N	01010000A034BF0D00906AF0AF2EA330C03418283FC22731C09A9999999999E93F
128	\N	\N	\N	\N	01010000A034BF0D005847053DAA6C2FC0284FC115B2242AC09A9999999999E93F
129	\N	\N	\N	\N	01010000A034BF0D00C043F5649C0133C068550ABE186B28C09A9999999999E93F
130	\N	\N	\N	\N	01010000A034BF0D00407F0EE7231034C0A83B7ACCFEAB2BC09A9999999999E93F
131	\N	\N	\N	\N	01010000A034BF0D00C043F5649C0133C0289D3316882B28C09A9999999999E93F
132	\N	\N	\N	\N	01010000A034BF0D00F80FE594552334C0541C6620062731C09A9999999999E93F
133	\N	\N	\N	\N	01010000A034BF0D003C0FFB33E41235C0284FC115B2242AC09A9999999999E93F
134	\N	\N	\N	\N	01010000A034BF0D004458A3AC7DFC38C068550ABE186B28C09A9999999999E93F
135	\N	\N	\N	\N	01010000A034BF0D00D818A880BDE937C0286F9AAF32AA2BC09A9999999999E93F
136	\N	\N	\N	\N	01010000A034BF0D004458A3AC7DFC38C0289D3316882B28C09A9999999999E93F
137	\N	\N	\N	\N	01010000A034BF0D002C4318C888D637C09C894580782A31C09A9999999999E93F
138	\N	\N	\N	\N	01010000A034BF0D009CA24B2517E636C0284FC115B2242AC09A9999999999E93F
139	\N	\N	\N	\N	01010000A034BF0D0068B4326F73253AC068550ABE186B28C09A9999999999E93F
140	\N	\N	\N	\N	01010000A034BF0D0024DF7C443B433BC01095F020C7AB2BC09A9999999999E93F
141	\N	\N	\N	\N	01010000A034BF0D0068B4326F73253AC0289D3316882B28C09A9999999999E93F
142	\N	\N	\N	\N	01010000A034BF0D0004F6522C64563BC074355418BA2931C09A9999999999E93F
143	\N	\N	\N	\N	01010000A034BF0D00C83B1535084B3CC0F84C7E6C9B1C2AC09A9999999999E93F
144	\N	\N	\N	\N	01010000A034BF0D00F4F457700FA33FC0286CC2FEA5D625C09A9999999999E93F
145	\N	\N	\N	\N	01010000A034BF0D00566393BE161540C0286CC2FEA5D625C09A9999999999E93F
146	\N	\N	\N	\N	01010000A034BF0D0078E87E10CFB340C0186CC2FEA5D625C09A9999999999E93F
147	\N	\N	\N	\N	01010000A034BF0D0036815F3DB26C43C0F86BC2FEA5D625C09A9999999999E93F
148	\N	\N	\N	\N	01010000A034BF0D007CF02BD09FA643C0F86BC2FEA5D625C09A9999999999E93F
149	\N	\N	\N	\N	01010000A034BF0D00D21AF9D64B0644C0F06BC2FEA5D625C09A9999999999E93F
150	\N	\N	\N	\N	01010000A034BF0D007EA01896F95A44C0E86BC2FEA5D625C09A9999999999E93F
151	\N	\N	\N	\N	01010000A034BF0D000A4E2C0A7F3945C0E06BC2FEA5D625C09A9999999999E93F
152	\N	\N	\N	\N	01010000A034BF0D00680B822BC0EC46C0C86BC2FEA5D625C09A9999999999E93F
153	\N	\N	\N	\N	01010000A034BF0D00221156A0D03E47C0C86BC2FEA5D625C09A9999999999E93F
154	\N	\N	\N	\N	01010000A034BF0D00A21559CF30AA47C0C06BC2FEA5D625C09A9999999999E93F
155	\N	\N	\N	\N	01010000A034BF0D00564489D303F247C0C06BC2FEA5D625C09A9999999999E93F
156	\N	\N	\N	\N	01010000A034BF0D0082B49270E59F4AC0986BC2FEA5D625C09A9999999999E93F
157	\N	\N	\N	\N	01010000A034BF0D004E6DE562C6E74AC0986BC2FEA5D625C09A9999999999E93F
158	\N	\N	\N	\N	01010000A034BF0D001A4E2C0A7F394BC0906BC2FEA5D625C09A9999999999E93F
159	\N	\N	\N	\N	01010000A034BF0D00BEAAEF396A984BC0906BC2FEA5D625C09A9999999999E93F
160	\N	\N	\N	\N	01010000A034BF0D0086B49270E55F4CC0886BC2FEA5D625C09A9999999999E93F
161	\N	\N	\N	\N	01010000A034BF0D00BE963790A6FC4DC0982FD38DE89425C09A9999999999E93F
162	\N	\N	\N	\N	01010000A034BF0D0071E8E793CF7950C058FC8391539327C09A9999999999E93F
163	\N	\N	\N	\N	01010000A034BF0D0009E94918F3B950C070E8FB28F59F27C09A9999999999E93F
164	\N	\N	\N	\N	01010000A034BF0D000B215CFFDAE050C070E8FB28F59F27C09A9999999999E93F
165	\N	\N	\N	\N	01010000A034BF0D0005B2C63F7EA051C070E8FB28F59F27C09A9999999999E93F
166	\N	\N	\N	\N	01010000A034BF0D0005B2C63F7EA051C0D076C63FED8E29C09A9999999999E93F
167	\N	\N	\N	\N	01010000A034BF0D00CBB62738E4E851C070E8FB28F59F27C09A9999999999E93F
168	\N	\N	\N	\N	01010000A034BF0D0095208A849EF351C070E8FB28F59F27C09A9999999999E93F
169	\N	\N	\N	\N	01010000A034BF0D000D40A11DB16152C0F8BDA57F49EC2AC09A9999999999E93F
170	\N	\N	\N	\N	01010000A034BF0D000D40A11DB16152C098378F0411B52FC09A9999999999E93F
171	\N	\N	\N	\N	01010000A034BF0D0015AF5FB3E79052C0F8BDA57F49EC2AC09A9999999999E93F
172	\N	\N	\N	\N	01010000A034BF0D007FDC7F2D95B752C0F8BDA57F49EC2AC09A9999999999E93F
173	\N	\N	\N	\N	01010000A034BF0D0071CFCA12276252C0D8AB83DC21FE20C09A9999999999E93F
174	\N	\N	\N	\N	01010000A034BF0D0071CFCA12276252C0B05F05658B5D1FC09A9999999999E93F
175	\N	\N	\N	\N	01010000A034BF0D00755CA765852252C0D8AB83DC21FE20C09A9999999999E93F
176	\N	\N	\N	\N	01010000A034BF0D0041E5377191D151C0E8E21A80081520C09A9999999999E93F
177	\N	\N	\N	\N	01010000A034BF0D0071CFCA12273252C0D8AB83DC21FE20C09A9999999999E93F
178	\N	\N	\N	\N	01010000A034BF0D00BDE1A681206D51C0E8E21A80081520C09A9999999999E93F
179	\N	\N	\N	\N	01010000A034BF0D006D1D9B4B54EF51C0D088E7334CAF1DC09A9999999999E93F
180	\N	\N	\N	\N	01010000A034BF0D001D1F5481CC0352C0E06D57D8C8671CC09A9999999999E93F
181	\N	\N	\N	\N	01010000A034BF0D00A18F30A7BFDD51C0B02AC32D53D816C09A9999999999E93F
182	\N	\N	\N	\N	01010000A034BF0D006D6DBFB4A2C051C0B02AC32D53D816C09A9999999999E93F
183	\N	\N	\N	\N	01010000A034BF0D00398590816F7D51C0B02AC32D53D816C09A9999999999E93F
184	\N	\N	\N	\N	01010000A034BF0D00398590816F7D51C0D06BAE083BFC12C09A9999999999E93F
185	\N	\N	\N	\N	01010000A034BF0D00118590816F7D51C0A0119B78979B0EC09A9999999999E93F
186	\N	\N	\N	\N	01010000A034BF0D00398590816F7D51C080F870FE635813C09A9999999999E93F
187	\N	\N	\N	\N	01010000A034BF0D00D33D983A013851C0D06BAE083BFC12C09A9999999999E93F
188	\N	\N	\N	\N	01010000A034BF0D005F33C196903A51C0E03EA86C0E910EC09A9999999999E93F
189	\N	\N	\N	\N	01010000A034BF0D00D33D983A013851C080F870FE635813C09A9999999999E93F
190	\N	\N	\N	\N	01010000A034BF0D006D6DBFB4A2C051C0D06BAE083BFC12C09A9999999999E93F
191	\N	\N	\N	\N	01010000A034BF0D004F6DBFB4A2C051C060119B78979B0EC09A9999999999E93F
192	\N	\N	\N	\N	01010000A034BF0D006D6DBFB4A2C051C080F870FE635813C09A9999999999E93F
193	\N	\N	\N	\N	01010000A034BF0D00D34E483C5E0552C080F870FE635813C09A9999999999E93F
194	\N	\N	\N	\N	01010000A034BF0D001D5111D6630652C0E0D3E0610A4813C09A9999999999E93F
195	\N	\N	\N	\N	01010000A034BF0D001D5111D6630652C02069AE083BFC12C09A9999999999E93F
196	\N	\N	\N	\N	01010000A034BF0D00475BE879D40352C060AB1840CD9B0EC09A9999999999E93F
197	\N	\N	\N	\N	01010000A034BF0D006753DA6F690752C080F870FE635813C09A9999999999E93F
198	\N	\N	\N	\N	01010000A034BF0D00898BBC2C391652C0904A640F871D14C09A9999999999E93F
199	\N	\N	\N	\N	01010000A034BF0D0005215CFFDAE050C0308D033138A42CC09A9999999999E93F
200	\N	\N	\N	\N	01010000A034BF0D009B9DC8D5A9C550C0B8C98A2B7DAA33C09A9999999999E93F
201	\N	\N	\N	\N	01010000A034BF0D0007215CFFDAE050C0C8269DCAD13D2CC09A9999999999E93F
202	\N	\N	\N	\N	01010000A034BF0D00C95671C5106C50C0B47605ED85B833C09A9999999999E93F
203	\N	\N	\N	\N	01010000A034BF0D0039548F320E1C51C0B8C98A2B7DAA33C09A9999999999E93F
204	\N	\N	\N	\N	01010000A034BF0D008B99DDEA2C5551C0B897E291E30034C09A9999999999E93F
205	\N	\N	\N	\N	01010000A034BF0D0039548F320E0C51C0B8C98A2B7DAA33C09A9999999999E93F
206	\N	\N	\N	\N	01010000A034BF0D00B9893B5B231252C02400ED43553733C09A9999999999E93F
207	\N	\N	\N	\N	01010000A034BF0D0039548F320E2C51C000AD1B735EA534C09A9999999999E93F
208	\N	\N	\N	\N	01010000A034BF0D00B76D2518584C50C00C73BC8BE09E31C09A9999999999E93F
209	\N	\N	\N	\N	01010000A034BF0D0027715965B01550C00C73BC8BE09E31C09A9999999999E93F
210	\N	\N	\N	\N	01010000A034BF0D00FACCDAAFEF344FC0CCE03282BCF032C09A9999999999E93F
211	\N	\N	\N	\N	01010000A034BF0D003DC11584372650C00C73BC8BE09E31C09A9999999999E93F
212	\N	\N	\N	\N	01010000A034BF0D007266B89BEF344FC0B00C1CCD67F832C09A9999999999E93F
213	\N	\N	\N	\N	01010000A034BF0D002ACE8A1230C74EC0F831B78AF12A32C09A9999999999E93F
214	\N	\N	\N	\N	01010000A034BF0D00EA7130D51B424EC06C651F7CF14A31C09A9999999999E93F
215	\N	\N	\N	\N	01010000A034BF0D0002377E00BD514EC0747176ECFA1133C09A9999999999E93F
216	\N	\N	\N	\N	01010000A034BF0D00B76D2518584C50C0CC4FF22413E231C09A9999999999E93F
217	\N	\N	\N	\N	01010000A034BF0D0085DC36B23D9950C018C2720549FE20C09A9999999999E93F
218	\N	\N	\N	\N	01010000A034BF0D00B626740340974DC02084700FA3F820C09A9999999999E93F
219	\N	\N	\N	\N	01010000A034BF0D00A2A11379631F4EC02084700FA3F820C09A9999999999E93F
220	\N	\N	\N	\N	01010000A034BF0D000A196671F6C14EC0C035E923800A20C09A9999999999E93F
221	\N	\N	\N	\N	01010000A034BF0D007A382FBFE7FD4DC02084700FA3F820C09A9999999999E93F
222	\N	\N	\N	\N	01010000A034BF0D003ADBB40582894FC0C035E923800A20C09A9999999999E93F
223	\N	\N	\N	\N	01010000A034BF0D007E87972A08874EC090AF1EB1B49E1DC09A9999999999E93F
224	\N	\N	\N	\N	01010000A034BF0D003637CF3EBAA54EC050D23B5DDCBD16C09A9999999999E93F
225	\N	\N	\N	\N	01010000A034BF0D00C2F75E5DC0E54EC050D23B5DDCBD16C09A9999999999E93F
226	\N	\N	\N	\N	01010000A034BF0D0032C8BCC3266C4FC050D23B5DDCBD16C09A9999999999E93F
227	\N	\N	\N	\N	01010000A034BF0D00A281797AB7F54FC040599F9BB6E112C09A9999999999E93F
228	\N	\N	\N	\N	01010000A034BF0D001A9627C298F04FC0808FD5649B470EC09A9999999999E93F
229	\N	\N	\N	\N	01010000A034BF0D009E81797AB7F54FC030EA6191DF3D13C09A9999999999E93F
230	\N	\N	\N	\N	01010000A034BF0D0046C8BCC3266C4FC040599F9BB6E112C09A9999999999E93F
231	\N	\N	\N	\N	01010000A034BF0D005EC8BCC3266C4FC040B905E4E1660EC09A9999999999E93F
232	\N	\N	\N	\N	01010000A034BF0D0042C8BCC3266C4FC030EA6191DF3D13C09A9999999999E93F
233	\N	\N	\N	\N	01010000A034BF0D00D6F75E5DC0E54EC040599F9BB6E112C09A9999999999E93F
234	\N	\N	\N	\N	01010000A034BF0D00E6F75E5DC0E54EC0C0B805E4E1660EC09A9999999999E93F
235	\N	\N	\N	\N	01010000A034BF0D00D2F75E5DC0E54EC030EA6191DF3D13C09A9999999999E93F
236	\N	\N	\N	\N	01010000A034BF0D00FAF10F4A34644EC040599F9BB6E112C09A9999999999E93F
237	\N	\N	\N	\N	01010000A034BF0D0026C4F309175E4EC0C0EDDBB4107B0EC09A9999999999E93F
238	\N	\N	\N	\N	01010000A034BF0D00FAF10F4A34644EC030EA6191DF3D13C09A9999999999E93F
239	\N	\N	\N	\N	01010000A034BF0D00662FF341625F4EC0D0EEFB6B85611CC09A9999999999E93F
240	\N	\N	\N	\N	01010000A034BF0D00B626740340974DC0B078244F36981FC09A9999999999E93F
241	\N	\N	\N	\N	01010000A034BF0D00DAB1C2ECD7114CC0680F4036204A23C09A9999999999E93F
242	\N	\N	\N	\N	01010000A034BF0D00F2BA11D6325C4CC0B0790C41C7AC17C09A9999999999E93F
243	\N	\N	\N	\N	01010000A034BF0D00DAB1C2ECD7114CC0F03951E7C38123C09A9999999999E93F
244	\N	\N	\N	\N	01010000A034BF0D00BEAAEF396A984BC068550ABE186B28C09A9999999999E93F
245	\N	\N	\N	\N	01010000A034BF0D002E4C9853B3FE4BC0D8D9AC243D842BC09A9999999999E93F
246	\N	\N	\N	\N	01010000A034BF0D00BEAAEF396A984BC0289D3316882B28C09A9999999999E93F
247	\N	\N	\N	\N	01010000A034BF0D00121A1B61E1114CC024F45A91932B31C09A9999999999E93F
248	\N	\N	\N	\N	01010000A034BF0D008A372226107D4CC068DDA7BF7C272AC09A9999999999E93F
249	\N	\N	\N	\N	01010000A034BF0D00724B5C8671EB4AC0D80E4036204A23C09A9999999999E93F
250	\N	\N	\N	\N	01010000A034BF0D00D6723B71F3314BC03039B25380A317C09A9999999999E93F
251	\N	\N	\N	\N	01010000A034BF0D00724B5C8671EB4AC0103A51E7C38123C09A9999999999E93F
252	\N	\N	\N	\N	01010000A034BF0D004E6DE562C6E74AC068550ABE186B28C09A9999999999E93F
253	\N	\N	\N	\N	01010000A034BF0D007AE91EFC805B4AC0A8281A828AAB2BC09A9999999999E93F
254	\N	\N	\N	\N	01010000A034BF0D004E6DE562C6E74AC0289D3316882B28C09A9999999999E93F
255	\N	\N	\N	\N	01010000A034BF0D000AC43961E1514AC0A49DDFC7092B31C09A9999999999E93F
256	\N	\N	\N	\N	01010000A034BF0D008A7B5F7BABDA49C060CAFCF650272AC09A9999999999E93F
257	\N	\N	\N	\N	01010000A034BF0D00DAB1C2ECD7514AC0680F4036204A23C09A9999999999E93F
258	\N	\N	\N	\N	01010000A034BF0D00E2709892A7074AC07048720F2BAD17C09A9999999999E93F
259	\N	\N	\N	\N	01010000A034BF0D00DAB1C2ECD7514AC0183A51E7C38123C09A9999999999E93F
260	\N	\N	\N	\N	01010000A034BF0D00564489D303F247C068550ABE186B28C09A9999999999E93F
261	\N	\N	\N	\N	01010000A034BF0D00AE1C522FB46E48C03882FAF9A6AA2BC09A9999999999E93F
262	\N	\N	\N	\N	01010000A034BF0D00564489D303F247C0289D3316882B28C09A9999999999E93F
263	\N	\N	\N	\N	01010000A034BF0D006E2AA0C7477848C03CA01D91932B31C09A9999999999E93F
264	\N	\N	\N	\N	01010000A034BF0D003A741992C2EF48C060CAFCF650272AC09A9999999999E93F
265	\N	\N	\N	\N	01010000A034BF0D003E1829533EF847C0680F4036204A23C09A9999999999E93F
266	\N	\N	\N	\N	01010000A034BF0D002A80F0CB5B7848C0B070F6186B1D1AC09A9999999999E93F
267	\N	\N	\N	\N	01010000A034BF0D003E1829533EF847C0583A51E7C38123C09A9999999999E93F
268	\N	\N	\N	\N	01010000A034BF0D00221156A0D03E47C068550ABE186B28C09A9999999999E93F
269	\N	\N	\N	\N	01010000A034BF0D0012360887E6C146C0C88F0EF08DAB2BC09A9999999999E93F
270	\N	\N	\N	\N	01010000A034BF0D00221156A0D03E47C0289D3316882B28C09A9999999999E93F
271	\N	\N	\N	\N	01010000A034BF0D007A9ABDC747B846C0C47D1AC8092B31C09A9999999999E93F
272	\N	\N	\N	\N	01010000A034BF0D0012890472084146C00067F7372B272AC09A9999999999E93F
273	\N	\N	\N	\N	01010000A034BF0D00020E52AFCD3A47C0680F4036204A23C09A9999999999E93F
274	\N	\N	\N	\N	01010000A034BF0D0036F00DCC5BB846C0D09EFDF7511E1AC09A9999999999E93F
275	\N	\N	\N	\N	01010000A034BF0D00020E52AFCD3A47C0683A51E7C38123C09A9999999999E93F
276	\N	\N	\N	\N	01010000A034BF0D00724B5C8671EB44C0680F4036204A23C09A9999999999E93F
277	\N	\N	\N	\N	01010000A034BF0D008E522D8DDA6A45C0B0E176D36AB215C09A9999999999E93F
278	\N	\N	\N	\N	01010000A034BF0D00724B5C8671EB44C0A03A51E7C38123C09A9999999999E93F
279	\N	\N	\N	\N	01010000A034BF0D007EA01896F95A44C068550ABE186B28C09A9999999999E93F
280	\N	\N	\N	\N	01010000A034BF0D0046693BBA19D544C0001B068CA3AA2BC09A9999999999E93F
281	\N	\N	\N	\N	01010000A034BF0D007EA01896F95A44C0289D3316882B28C09A9999999999E93F
282	\N	\N	\N	\N	01010000A034BF0D00E200242EAEDE44C020C0E290932B31C09A9999999999E93F
283	\N	\N	\N	\N	01010000A034BF0D007A334168325645C00067F7372B272AC09A9999999999E93F
284	\N	\N	\N	\N	01010000A034BF0D003E1829533EB843C0680F4036204A23C09A9999999999E93F
285	\N	\N	\N	\N	01010000A034BF0D00D07375614F4144C0F025328ABFAD15C09A9999999999E93F
286	\N	\N	\N	\N	01010000A034BF0D003E1829533EB843C0C03A51E7C38123C09A9999999999E93F
287	\N	\N	\N	\N	01010000A034BF0D007CF02BD09FA643C068550ABE186B28C09A9999999999E93F
288	\N	\N	\N	\N	01010000A034BF0D00DE9E06145A2843C04086AE5559AB2BC09A9999999999E93F
289	\N	\N	\N	\N	01010000A034BF0D007CF02BD09FA643C0289D3316882B28C09A9999999999E93F
290	\N	\N	\N	\N	01010000A034BF0D00225BD42DAC1E43C040327BC7052B31C09A9999999999E93F
291	\N	\N	\N	\N	01010000A034BF0D00E080118D64A742C098AC910A02272AC09A9999999999E93F
292	\N	\N	\N	\N	01010000A034BF0D00A67E8FB9A41E43C0680F4036204A23C09A9999999999E93F
293	\N	\N	\N	\N	01010000A034BF0D00001B489B83D442C0407E2B428ED117C09A9999999999E93F
294	\N	\N	\N	\N	01010000A034BF0D00A67E8FB9A41E43C0D03A51E7C38123C09A9999999999E93F
295	\N	\N	\N	\N	01010000A034BF0D0078E87E10CFB340C068550ABE186B28C09A9999999999E93F
296	\N	\N	\N	\N	01010000A034BF0D002A29A0372B3B41C030C8CC6460AC2BC09A9999999999E93F
297	\N	\N	\N	\N	01010000A034BF0D0078E87E10CFB340C0289D3316882B28C09A9999999999E93F
298	\N	\N	\N	\N	01010000A034BF0D00A018A184B04441C048533AC48B2931C09A9999999999E93F
299	\N	\N	\N	\N	01010000A034BF0D007C08011AA3BC41C098AC910A02272AC09A9999999999E93F
300	\N	\N	\N	\N	01010000A034BF0D00566393BE161540C068550ABE186B28C09A9999999999E93F
301	\N	\N	\N	\N	01010000A034BF0D00F48BE788A21C3FC0303CC6B005AA2BC09A9999999999E93F
302	\N	\N	\N	\N	01010000A034BF0D00566393BE161540C0289D3316882B28C09A9999999999E93F
303	\N	\N	\N	\N	01010000A034BF0D006C3C570A65093FC03C29AF39862A31C09A9999999999E93F
304	\N	\N	\N	\N	01010000A034BF0D00F0CC227D24163EC0F84C7E6C9B1C2AC09A9999999999E93F
305	\N	\N	\N	\N	01010000A034BF0D00FEFCFB3B951F40C0680F4036204A23C09A9999999999E93F
306	\N	\N	\N	\N	01010000A034BF0D000ACEA353A31E41C0D038D4A7392C1CC09A9999999999E93F
307	\N	\N	\N	\N	01010000A034BF0D00FEFCFB3B951F40C0183B51E7C38123C09A9999999999E93F
308	\N	\N	\N	\N	01010000A034BF0D00609E71E1904427C090039A7CEE912DC09A9999999999E93F
309	\N	\N	\N	\N	01010000A034BF0D00F87D8A907CF124C05807A30C40F631C09A9999999999E93F
310	\N	\N	\N	\N	01010000A034BF0D00CBB62738E4E851C0308D033138A42DC09A9999999999E93F
311	\N	\N	\N	\N	01010000A034BF0D0089855B35799E51C044E93BEB08DE31C09A9999999999E93F
312	\N	\N	\N	\N	01010000A034BF0D00B692D5108DFD4DC000245E4E0E412CC00000000000000840
313	\N	\N	\N	\N	01010000A034BF0D00D24212692D984DC070E450AF8FAB2AC00000000000000840
314	\N	\N	\N	\N	01010000A034BF0D00D24212692D984DC0880F09DE84662AC00000000000000840
315	\N	\N	\N	\N	01010000A034BF0D00E675459C60B34DC090D498BCE34728C00000000000000840
316	\N	\N	\N	\N	01010000A034BF0D00E675459C60B34DC0980705A102E425C00000000000000840
317	\N	\N	\N	\N	01010000A034BF0D00E675459C60B34DC0E8665D4DB8C728C00000000000000840
318	\N	\N	\N	\N	01010000A034BF0D00E2C9D754D2004EC068EA1A4C939D25C00000000000000840
319	\N	\N	\N	\N	01010000A034BF0D00AEC273CF07EC4FC078C1BEBCD0A727C00000000000000840
320	\N	\N	\N	\N	01010000A034BF0D00BB735325F37350C078C1BEBCD0A727C00000000000000840
321	\N	\N	\N	\N	01010000A034BF0D0007215CFFDAE050C0A8AAA3CFEFAF27C00000000000000840
322	\N	\N	\N	\N	01010000A034BF0D0039548F320E1C51C024CA8A2B7DAA33C00000000000000840
323	\N	\N	\N	\N	01010000A034BF0D008B99DDEA2C5551C0B897E291E30034C00000000000000840
324	\N	\N	\N	\N	01010000A034BF0D0039548F320E0C51C024CA8A2B7DAA33C00000000000000840
325	\N	\N	\N	\N	01010000A034BF0D0007215CFFDAE050C08842CD9CEABD2CC00000000000000840
326	\N	\N	\N	\N	01010000A034BF0D0007215CFFDAE050C0A882E09D5E5C2CC00000000000000840
327	\N	\N	\N	\N	01010000A034BF0D00B9893B5B231252C02400ED43553733C00000000000000840
328	\N	\N	\N	\N	01010000A034BF0D0039548F320E2C51C000AD1B735EA534C00000000000000840
329	\N	\N	\N	\N	01010000A034BF0D003B548F320E5451C0A8AAA3CFEFAF27C00000000000000840
330	\N	\N	\N	\N	01010000A034BF0D0061EC4408028D51C0A8AAA3CFEFAF27C00000000000000840
331	\N	\N	\N	\N	01010000A034BF0D00F14DD1D4FB9F51C008321BE2052929C00000000000000840
332	\N	\N	\N	\N	01010000A034BF0D009D1B45160EF251C098D3FF5EB2A527C00000000000000840
333	\N	\N	\N	\N	01010000A034BF0D00C9129CB2916052C090BCA57F49EC2AC00000000000000840
334	\N	\N	\N	\N	01010000A034BF0D00C9129CB2916052C0F875EB3545AC2FC00000000000000840
335	\N	\N	\N	\N	01010000A034BF0D00C9129CB2919052C090BCA57F49EC2AC00000000000000840
336	\N	\N	\N	\N	01010000A034BF0D0083DC7F2D95B752C090BCA57F49EC2AC00000000000000840
337	\N	\N	\N	\N	01010000A034BF0D001DB0D345E36152C0C8AB83DC21FE20C00000000000000840
338	\N	\N	\N	\N	01010000A034BF0D001DB0D345E36152C060A81CDBA65D1FC00000000000000840
339	\N	\N	\N	\N	01010000A034BF0D00755CA765852252C0C8AB83DC21FE20C00000000000000840
340	\N	\N	\N	\N	01010000A034BF0D0041E5377191D151C0E8E21A80081520C00000000000000840
341	\N	\N	\N	\N	01010000A034BF0D00755CA765853252C0C8AB83DC21FE20C00000000000000840
342	\N	\N	\N	\N	01010000A034BF0D00BDE1A681206D51C0E8E21A80081520C00000000000000840
343	\N	\N	\N	\N	01010000A034BF0D006D1D9B4B54EF51C0D088E7334CAF1DC00000000000000840
344	\N	\N	\N	\N	01010000A034BF0D001D1F5481CC0352C0E06D57D8C8671CC00000000000000840
345	\N	\N	\N	\N	01010000A034BF0D00A18F30A7BFDD51C0B02AC32D53D816C00000000000000840
346	\N	\N	\N	\N	01010000A034BF0D006D6DBFB4A2C051C0B02AC32D53D816C00000000000000840
347	\N	\N	\N	\N	01010000A034BF0D00398590816F7D51C0B02AC32D53D816C00000000000000840
348	\N	\N	\N	\N	01010000A034BF0D00398590816F7D51C0D06BAE083BFC12C00000000000000840
349	\N	\N	\N	\N	01010000A034BF0D00118590816F7D51C0A0119B78979B0EC00000000000000840
350	\N	\N	\N	\N	01010000A034BF0D00398590816F7D51C080F870FE635813C00000000000000840
351	\N	\N	\N	\N	01010000A034BF0D00D33D983A013851C0D06BAE083BFC12C00000000000000840
352	\N	\N	\N	\N	01010000A034BF0D005F33C196903A51C0E03EA86C0E910EC00000000000000840
353	\N	\N	\N	\N	01010000A034BF0D00D33D983A013851C080F870FE635813C00000000000000840
354	\N	\N	\N	\N	01010000A034BF0D006D6DBFB4A2C051C0D06BAE083BFC12C00000000000000840
355	\N	\N	\N	\N	01010000A034BF0D004F6DBFB4A2C051C060119B78979B0EC00000000000000840
356	\N	\N	\N	\N	01010000A034BF0D006D6DBFB4A2C051C080F870FE635813C00000000000000840
357	\N	\N	\N	\N	01010000A034BF0D00D34E483C5E0552C080F870FE635813C00000000000000840
358	\N	\N	\N	\N	01010000A034BF0D001D5111D6630652C0E0D3E0610A4813C00000000000000840
359	\N	\N	\N	\N	01010000A034BF0D006753DA6F690752C080F870FE635813C00000000000000840
360	\N	\N	\N	\N	01010000A034BF0D00898BBC2C391652C0904A640F871D14C00000000000000840
361	\N	\N	\N	\N	01010000A034BF0D001D5111D6630652C02069AE083BFC12C00000000000000840
362	\N	\N	\N	\N	01010000A034BF0D00475BE879D40352C060AB1840CD9B0EC00000000000000840
363	\N	\N	\N	\N	01010000A034BF0D0099AA3DB0479850C0F070D3CB92EB20C00000000000000840
364	\N	\N	\N	\N	01010000A034BF0D00AEC273CF07EC4FC0E849C9C798C22CC00000000000000840
365	\N	\N	\N	\N	01010000A034BF0D0092957199842F4FC0407371D3FE5830C00000000000000840
366	\N	\N	\N	\N	01010000A034BF0D00AEC273CF07EC4FC0A882E09D5E5C2CC00000000000000840
367	\N	\N	\N	\N	01010000A034BF0D0046EE2307832F4FC0B8F184A14B5A31C00000000000000840
368	\N	\N	\N	\N	01010000A034BF0D0002377E00BD514EC0747176ECFA1133C00000000000000840
369	\N	\N	\N	\N	01010000A034BF0D0066B76A90ED344FC03C09A0E36BF832C00000000000000840
370	\N	\N	\N	\N	01010000A034BF0D004A4575C6C2EA4EC0487D2B3347F32FC00000000000000840
371	\N	\N	\N	\N	01010000A034BF0D003AF6335C46984DC01084700FA3F820C00000000000000840
372	\N	\N	\N	\N	01010000A034BF0D00A2A11379631F4EC01084700FA3F820C00000000000000840
373	\N	\N	\N	\N	01010000A034BF0D000A196671F6C14EC0C035E923800A20C00000000000000840
374	\N	\N	\N	\N	01010000A034BF0D0082D7AE70F4FF4DC01084700FA3F820C00000000000000840
375	\N	\N	\N	\N	01010000A034BF0D003ADBB40582894FC0C035E923800A20C00000000000000840
376	\N	\N	\N	\N	01010000A034BF0D007E87972A08874EC090AF1EB1B49E1DC00000000000000840
377	\N	\N	\N	\N	01010000A034BF0D003637CF3EBAA54EC050D23B5DDCBD16C00000000000000840
378	\N	\N	\N	\N	01010000A034BF0D00C2F75E5DC0E54EC050D23B5DDCBD16C00000000000000840
379	\N	\N	\N	\N	01010000A034BF0D0032C8BCC3266C4FC050D23B5DDCBD16C00000000000000840
380	\N	\N	\N	\N	01010000A034BF0D00A681797AB7F54FC040599F9BB6E112C00000000000000840
381	\N	\N	\N	\N	01010000A034BF0D001A9627C298F04FC0808FD5649B470EC00000000000000840
382	\N	\N	\N	\N	01010000A034BF0D00A281797AB7F54FC030EA6191DF3D13C00000000000000840
383	\N	\N	\N	\N	01010000A034BF0D0046C8BCC3266C4FC040599F9BB6E112C00000000000000840
384	\N	\N	\N	\N	01010000A034BF0D005EC8BCC3266C4FC040B905E4E1660EC00000000000000840
385	\N	\N	\N	\N	01010000A034BF0D0042C8BCC3266C4FC030EA6191DF3D13C00000000000000840
386	\N	\N	\N	\N	01010000A034BF0D00D6F75E5DC0E54EC040599F9BB6E112C00000000000000840
387	\N	\N	\N	\N	01010000A034BF0D00E6F75E5DC0E54EC0C0B805E4E1660EC00000000000000840
388	\N	\N	\N	\N	01010000A034BF0D00D2F75E5DC0E54EC030EA6191DF3D13C00000000000000840
389	\N	\N	\N	\N	01010000A034BF0D00FAF10F4A34644EC040599F9BB6E112C00000000000000840
390	\N	\N	\N	\N	01010000A034BF0D0026C4F309175E4EC0C0EDDBB4107B0EC00000000000000840
391	\N	\N	\N	\N	01010000A034BF0D00FAF10F4A34644EC030EA6191DF3D13C00000000000000840
392	\N	\N	\N	\N	01010000A034BF0D00662FF341625F4EC0D0EEFB6B85611CC00000000000000840
393	\N	\N	\N	\N	01010000A034BF0D003AF6335C46984DC0401FBFA2D79E1FC00000000000000840
394	\N	\N	\N	\N	01010000A034BF0D00F6B180612A134CC068A7AD1237D725C00000000000000840
395	\N	\N	\N	\N	01010000A034BF0D0076BF72FA34EA4AC068A7AD1237D725C00000000000000840
396	\N	\N	\N	\N	01010000A034BF0D002230B0040C4E4AC0E0138A0BBFF526C00000000000000840
397	\N	\N	\N	\N	01010000A034BF0D006AA776C5A31E4AC0C836700860B327C00000000000000840
398	\N	\N	\N	\N	01010000A034BF0D00FA74D8DA927948C0C836700860B327C00000000000000840
399	\N	\N	\N	\N	01010000A034BF0D008277BC0637E547C0C836700860B327C00000000000000840
400	\N	\N	\N	\N	01010000A034BF0D00D21849189D5047C0C836700860B327C00000000000000840
401	\N	\N	\N	\N	01010000A034BF0D00D21849189D5047C0A8FCC28A664523C00000000000000840
402	\N	\N	\N	\N	01010000A034BF0D001AFAC32C4B9847C090237F4BD4C617C00000000000000840
403	\N	\N	\N	\N	01010000A034BF0D00D21849189D5047C0A03A7185218023C00000000000000840
404	\N	\N	\N	\N	01010000A034BF0D00EADD226D9D4B47C0C836700860B327C00000000000000840
405	\N	\N	\N	\N	01010000A034BF0D0046C63E9D2FDE46C0C836700860B327C00000000000000840
406	\N	\N	\N	\N	01010000A034BF0D00387FAF7E03B746C0901A338EAF1627C00000000000000840
407	\N	\N	\N	\N	01010000A034BF0D00387FAF7E03B746C058FCC28A664523C00000000000000840
408	\N	\N	\N	\N	01010000A034BF0D00685F59C0606E46C07018599A79CE17C00000000000000840
409	\N	\N	\N	\N	01010000A034BF0D00387FAF7E03B746C0A03A7185218023C00000000000000840
410	\N	\N	\N	\N	01010000A034BF0D00085C4E6B9D4B45C058D009A2F9CC25C00000000000000840
411	\N	\N	\N	\N	01010000A034BF0D00085C4E6B9D4B45C058FCC28A664523C00000000000000840
412	\N	\N	\N	\N	01010000A034BF0D008E522D8DDA6A45C0B0E176D36AB215C00000000000000840
413	\N	\N	\N	\N	01010000A034BF0D00085C4E6B9D4B45C0A03A7185218023C00000000000000840
414	\N	\N	\N	\N	01010000A034BF0D00A2F5E704372543C058D009A2F9CC25C00000000000000840
415	\N	\N	\N	\N	01010000A034BF0D00A2F5E704372543C058FCC28A664523C00000000000000840
416	\N	\N	\N	\N	01010000A034BF0D000C525BF8121F43C0A036C52A09261AC00000000000000840
417	\N	\N	\N	\N	01010000A034BF0D00A2F5E704372543C0A03A7185218023C00000000000000840
418	\N	\N	\N	\N	01010000A034BF0D002673E369714B41C058D009A2F9CC25C00000000000000840
419	\N	\N	\N	\N	01010000A034BF0D002673E369714B41C058FCC28A664523C00000000000000840
420	\N	\N	\N	\N	01010000A034BF0D0070060287BF4441C07081695DA1201AC00000000000000840
421	\N	\N	\N	\N	01010000A034BF0D002673E369714B41C0A03A7185218023C00000000000000840
422	\N	\N	\N	\N	01010000A034BF0D00A28CEF4DD9CA40C058D009A2F9CC25C00000000000000840
423	\N	\N	\N	\N	01010000A034BF0D00E47F606D7C303EC058D009A2F9CC25C00000000000000840
424	\N	\N	\N	\N	01010000A034BF0D00E47F606D7C303EC058FCC28A664523C00000000000000840
425	\N	\N	\N	\N	01010000A034BF0D000AC1ECAFF11740C0C010C4DDC78B15C00000000000000840
426	\N	\N	\N	\N	01010000A034BF0D00E47F606D7C303EC0A03A7185218023C00000000000000840
427	\N	\N	\N	\N	01010000A034BF0D00F45BF6C287593BC0A89F80F1911227C00000000000000840
428	\N	\N	\N	\N	01010000A034BF0D00AC71F9CBCE103BC038747ADF03A427C00000000000000840
429	\N	\N	\N	\N	01010000A034BF0D00309F81187B303AC038747ADF03A427C00000000000000840
430	\N	\N	\N	\N	01010000A034BF0D00C428C38F54263AC038747ADF03A427C00000000000000840
431	\N	\N	\N	\N	01010000A034BF0D00C428C38F54263AC088FDC28A664523C00000000000000840
432	\N	\N	\N	\N	01010000A034BF0D00C066CD66F89639C030BED003F3CB17C00000000000000840
433	\N	\N	\N	\N	01010000A034BF0D00C428C38F54263AC0A03A7185218023C00000000000000840
434	\N	\N	\N	\N	01010000A034BF0D00FC6B4EE547FD38C038747ADF03A427C00000000000000840
435	\N	\N	\N	\N	01010000A034BF0D007070A40A69D437C038747ADF03A427C00000000000000840
436	\N	\N	\N	\N	01010000A034BF0D007070A40A69D437C058FCC28A664523C00000000000000840
437	\N	\N	\N	\N	01010000A034BF0D003C1A9971234337C0700827C498D317C00000000000000840
438	\N	\N	\N	\N	01010000A034BF0D007070A40A69D437C0A03A7185218023C00000000000000840
439	\N	\N	\N	\N	01010000A034BF0D001478CFF27D8134C038747ADF03A427C00000000000000840
440	\N	\N	\N	\N	01010000A034BF0D00645D6EE8582634C0D83EB8CAB9ED26C00000000000000840
441	\N	\N	\N	\N	01010000A034BF0D00645D6EE8582634C058FCC28A664523C00000000000000840
442	\N	\N	\N	\N	01010000A034BF0D00AC62367FA0B734C0E030C80282CE17C00000000000000840
443	\N	\N	\N	\N	01010000A034BF0D00645D6EE8582634C0A03A7185218023C00000000000000840
444	\N	\N	\N	\N	01010000A034BF0D00302A3BB525F332C058D009A2F9CC25C00000000000000840
445	\N	\N	\N	\N	01010000A034BF0D0024B4F1A7B3A030C058D009A2F9CC25C00000000000000840
446	\N	\N	\N	\N	01010000A034BF0D0070E5CB16888E29C0A0C8AB774CA125C00000000000000840
447	\N	\N	\N	\N	01010000A034BF0D00F8788019788324C0D8EDB5F420A327C00000000000000840
448	\N	\N	\N	\N	01010000A034BF0D00005EA33F689E22C0D8EDB5F420A327C00000000000000840
449	\N	\N	\N	\N	01010000A034BF0D0060347A8B256C17C0F0C85F011B9E27C00000000000000840
450	\N	\N	\N	\N	01010000A034BF0D0070B4213EB5C014C0F0C85F011B9E27C00000000000000840
451	\N	\N	\N	\N	01010000A034BF0D0080DCB2204E8804C0F0C85F011B9E27C00000000000000840
452	\N	\N	\N	\N	01010000A034BF0D00004C1A109A22E93F28897F828FFD20C00000000000000840
453	\N	\N	\N	\N	01010000A034BF0D000010C12DEE49CFBF28897F828FFD20C00000000000000840
454	\N	\N	\N	\N	01010000A034BF0D0040BDD35CC1B5F7BFE8968166ED1A20C00000000000000840
455	\N	\N	\N	\N	01010000A034BF0D000000DE473AC2763F28897F828FFD20C00000000000000840
456	\N	\N	\N	\N	01010000A034BF0D0080235D8414FB08C0E8968166ED1A20C00000000000000840
457	\N	\N	\N	\N	01010000A034BF0D0080F5B51E2CD5F0BFE088E89125971DC00000000000000840
458	\N	\N	\N	\N	01010000A034BF0D0000172739EF64F5BF4034A69E5BEE16C00000000000000840
459	\N	\N	\N	\N	01010000A034BF0D00C08C2C52A73CFCBF4034A69E5BEE16C00000000000000840
460	\N	\N	\N	\N	01010000A034BF0D00004DF30EBA8406C04034A69E5BEE16C00000000000000840
461	\N	\N	\N	\N	01010000A034BF0D008060E6C8A14C0FC0208876BC630013C00000000000000840
462	\N	\N	\N	\N	01010000A034BF0D0040A9C743B6FA0EC080A98C83D4800EC00000000000000840
463	\N	\N	\N	\N	01010000A034BF0D008060E6C8A14C0FC0301739B28C5C13C00000000000000840
464	\N	\N	\N	\N	01010000A034BF0D00004DF30EBA8406C0208876BC630013C00000000000000840
465	\N	\N	\N	\N	01010000A034BF0D00804EF30EBA8406C0C05495B43E710EC00000000000000840
466	\N	\N	\N	\N	01010000A034BF0D00004DF30EBA8406C0301739B28C5C13C00000000000000840
467	\N	\N	\N	\N	01010000A034BF0D00C08C2C52A73CFCBF208876BC630013C00000000000000840
468	\N	\N	\N	\N	01010000A034BF0D00008E2C52A73CFCBFC05495B43E710EC00000000000000840
469	\N	\N	\N	\N	01010000A034BF0D00C08C2C52A73CFCBF301739B28C5C13C00000000000000840
470	\N	\N	\N	\N	01010000A034BF0D0000B15DBEEEBAE8BF301739B28C5C13C00000000000000840
471	\N	\N	\N	\N	01010000A034BF0D000092B9B7F7D5E7BF80CB21856B3C13C00000000000000840
472	\N	\N	\N	\N	01010000A034BF0D000092B9B7F7D5E7BF208876BC630013C00000000000000840
473	\N	\N	\N	\N	01010000A034BF0D00007834CCA51DE7BF0078C184C2610EC00000000000000840
474	\N	\N	\N	\N	01010000A034BF0D008034FF4EEED4E6BF301739B28C5C13C00000000000000840
475	\N	\N	\N	\N	01010000A034BF0D00002DA4B8CFD2DBBFB0D5E8FACB1914C00000000000000840
476	\N	\N	\N	\N	01010000A034BF0D008003FADFAE0FE6BFF04B3A66D0231CC00000000000000840
477	\N	\N	\N	\N	01010000A034BF0D00004C1A109A22E93F8095376C5B421FC00000000000000840
478	\N	\N	\N	\N	01010000A034BF0D004069437C6A810CC060D06649BBDE2CC00000000000000840
479	\N	\N	\N	\N	01010000A034BF0D00207863FE4CE802C0BCCCD5BAE76830C00000000000000840
480	\N	\N	\N	\N	01010000A034BF0D004069437C6A810CC0C8BA8D5CEB5A2CC00000000000000840
481	\N	\N	\N	\N	01010000A034BF0D00207863FE4CE802C0C4FD4CF775E630C00000000000000840
482	\N	\N	\N	\N	01010000A034BF0D00802FA1F870ABE8BF747473F0CD5C32C00000000000000840
483	\N	\N	\N	\N	01010000A034BF0D0040C6E66CB0FC02C0FC189D930EA931C00000000000000840
484	\N	\N	\N	\N	01010000A034BF0D0040C6E66CB0FC02C0C4E2A3B0264E35C00000000000000840
485	\N	\N	\N	\N	01010000A034BF0D0000CA6284DCA501C0EC9F3233925235C00000000000000840
486	\N	\N	\N	\N	01010000A034BF0D00E0BDD788106302C0AC98E401388535C00000000000000840
487	\N	\N	\N	\N	01010000A034BF0D006050BBD74E5A12C0FC189D930EA931C00000000000000840
488	\N	\N	\N	\N	01010000A034BF0D00400781AB8F8B19C0FC189D930EA931C00000000000000840
489	\N	\N	\N	\N	01010000A034BF0D00404EBBD74E5A11C0FC189D930EA931C00000000000000840
490	\N	\N	\N	\N	01010000A034BF0D00400781AB8F8B19C0EC12A61DAB9433C00000000000000840
491	\N	\N	\N	\N	01010000A034BF0D00F05DA33F68DE20C0A4D0749DE5AC35C00000000000000840
492	\N	\N	\N	\N	01010000A034BF0D00308A991BCBF222C0A483A722F33E36C00000000000000840
493	\N	\N	\N	\N	01010000A034BF0D00105FA33F685E20C0A4D0749DE5AC35C00000000000000840
494	\N	\N	\N	\N	01010000A034BF0D00F8CABD00F0FD26C0244846A9593E36C00000000000000840
495	\N	\N	\N	\N	01010000A034BF0D0078B7711D6F3B21C0FC6CBB21A11A37C00000000000000840
496	\N	\N	\N	\N	01010000A034BF0D00F05DA33F68DE20C0EC12A61DAB9433C00000000000000840
497	\N	\N	\N	\N	01010000A034BF0D00D84014EA1F7127C054B90F6DE02934C00000000000000840
498	\N	\N	\N	\N	01010000A034BF0D00105FA33F685E20C0EC12A61DAB9433C00000000000000840
499	\N	\N	\N	\N	01010000A034BF0D0070B4213EB5C014C0B00C467B70462CC00000000000000840
500	\N	\N	\N	\N	01010000A034BF0D0070B4213EB5C014C0409C1657F7752CC00000000000000840
501	\N	\N	\N	\N	01010000A034BF0D00004CEF09953DE9BFFC302EA7991931C00000000000000840
502	\N	\N	\N	\N	01010000A034BF0D00301A9ED3BD9619C0407B8399F92BFEBF0000000000000840
503	\N	\N	\N	\N	01010000A034BF0D00301A9ED3BD9619C0C0DB85ACAD86FDBF0000000000000840
504	\N	\N	\N	\N	01010000A034BF0D00301A9ED3BD9619C0C0F21BF96249FCBF0000000000000840
505	\N	\N	\N	\N	01010000A034BF0D006079F527AB7011C0C0DB85ACAD86FDBF0000000000000840
506	\N	\N	\N	\N	01010000A034BF0D0000C3E64694CDF4BF80D1E64694CDF4BF0000000000000840
507	\N	\N	\N	\N	01010000A034BF0D008078F527AB7012C0C0DB85ACAD86FDBF0000000000000840
508	\N	\N	\N	\N	01010000A034BF0D00F05DA33F68DE20C0407B8399F92BFEBF0000000000000840
509	\N	\N	\N	\N	01010000A034BF0D001079B440D10C27C080F0E816D5DAF3BF0000000000000840
510	\N	\N	\N	\N	01010000A034BF0D00F05DA33F685E20C0407B8399F92BFEBF0000000000000840
511	\N	\N	\N	\N	01010000A034BF0D0050A4B0C2940825C0909B9E7061F128C00000000000000840
512	\N	\N	\N	\N	01010000A034BF0D00F00461169C2D2BC010E0328373FB20C00000000000000840
513	\N	\N	\N	\N	01010000A034BF0D00F00461169C2D2BC080856023A4371FC00000000000000840
514	\N	\N	\N	\N	01010000A034BF0D001865BD4E9F1129C010E0328373FB20C00000000000000840
515	\N	\N	\N	\N	01010000A034BF0D00D84F6758E4EA26C0500EA35738771FC00000000000000840
516	\N	\N	\N	\N	01010000A034BF0D003091D6729B9129C010E0328373FB20C00000000000000840
517	\N	\N	\N	\N	01010000A034BF0D00A85F773F685E23C0F8316F5BDB1420C00000000000000840
518	\N	\N	\N	\N	01010000A034BF0D00C81ADF741A7827C060D6707B0C011DC00000000000000840
519	\N	\N	\N	\N	01010000A034BF0D001084D38C95E328C040325D3A1A2A1AC00000000000000840
520	\N	\N	\N	\N	01010000A034BF0D0028A17C8670EB26C0B078FB1B55E716C00000000000000840
521	\N	\N	\N	\N	01010000A034BF0D0088AE9C064B0F26C0B078FB1B55E716C00000000000000840
522	\N	\N	\N	\N	01010000A034BF0D00E06C256DB1F523C0B078FB1B55E716C00000000000000840
523	\N	\N	\N	\N	01010000A034BF0D00E06C256DB1F523C0F0F826E7590B13C00000000000000840
524	\N	\N	\N	\N	01010000A034BF0D00C06C256DB1F523C0606A3F6271870EC00000000000000840
525	\N	\N	\N	\N	01010000A034BF0D00E06C256DB1F523C0A086E9DC826713C00000000000000840
526	\N	\N	\N	\N	01010000A034BF0D0088E0DC5CA2C321C0F0F826E7590B13C00000000000000840
527	\N	\N	\N	\N	01010000A034BF0D006090243E1DD821C02099CA851A970EC00000000000000840
528	\N	\N	\N	\N	01010000A034BF0D0088E0DC5CA2C321C0A086E9DC826713C00000000000000840
529	\N	\N	\N	\N	01010000A034BF0D0088AE9C064B0F26C0F0F826E7590B13C00000000000000840
530	\N	\N	\N	\N	01010000A034BF0D00A0AE9C064B0F26C0A026A42F30870EC00000000000000840
531	\N	\N	\N	\N	01010000A034BF0D0088AE9C064B0F26C0A086E9DC826713C00000000000000840
532	\N	\N	\N	\N	01010000A034BF0D00307CAFA8562828C050F726E7590B13C00000000000000840
533	\N	\N	\N	\N	01010000A034BF0D0078DEA186893028C0C032422BF4FA12C00000000000000840
534	\N	\N	\N	\N	01010000A034BF0D00280AB6A6490728C0A086E9DC826713C00000000000000840
535	\N	\N	\N	\N	01010000A034BF0D00700AB2397E0228C0A0D1B7C8D7ED0DC00000000000000840
536	\N	\N	\N	\N	01010000A034BF0D00688875DFD06628C0A086E9DC826713C00000000000000840
537	\N	\N	\N	\N	01010000A034BF0D00688C0E9784C628C0104151638BFE13C00000000000000840
538	\N	\N	\N	\N	01010000A034BF0D00C0409464BC3828C050F726E7590B13C00000000000000840
539	\N	\N	\N	\N	01010000A034BF0D0024B4F1A7B3A030C058FCC28A664523C00000000000000840
540	\N	\N	\N	\N	01010000A034BF0D008C8EDE26AF0F30C0B048466494D217C00000000000000840
541	\N	\N	\N	\N	01010000A034BF0D0024B4F1A7B3A030C0A03A7185218023C00000000000000840
542	\N	\N	\N	\N	01010000A034BF0D00302A3BB525F332C058FCC28A664523C00000000000000840
543	\N	\N	\N	\N	01010000A034BF0D0098083048866332C06036261400CD17C00000000000000840
544	\N	\N	\N	\N	01010000A034BF0D00302A3BB525F332C0A03A7185218023C00000000000000840
545	\N	\N	\N	\N	01010000A034BF0D00885684B57FF232C0B06683A6FB8B15C00000000000000840
546	\N	\N	\N	\N	01010000A034BF0D00D0CE647C4E4F32C0404FF9E4207C17C00000000000000840
547	\N	\N	\N	\N	01010000A034BF0D00F458A3AC7DFC32C0682CAE2E56B52AC00000000000000840
548	\N	\N	\N	\N	01010000A034BF0D00686D51F45E5732C0682CAE2E56B52AC00000000000000840
549	\N	\N	\N	\N	01010000A034BF0D00C4AFACCE5FCA30C01837BA6F7D6B2BC00000000000000840
550	\N	\N	\N	\N	01010000A034BF0D0048DBCAC58C6F32C0682CAE2E56B52AC00000000000000840
551	\N	\N	\N	\N	01010000A034BF0D0000A8FA86D2A330C0C4DA1D681E2731C00000000000000840
552	\N	\N	\N	\N	01010000A034BF0D002014D20977792FC06082F448E5172AC00000000000000840
553	\N	\N	\N	\N	01010000A034BF0D00F458A3AC7DFC32C0608DBFFA29042CC00000000000000840
554	\N	\N	\N	\N	01010000A034BF0D0088D2DABDB12234C0E4DE5B49622631C00000000000000840
555	\N	\N	\N	\N	01010000A034BF0D00F458A3AC7DFC32C0C8AD8339E6C72BC00000000000000840
556	\N	\N	\N	\N	01010000A034BF0D00FC6B4EE547FD38C0608DBFFA29042CC00000000000000840
557	\N	\N	\N	\N	01010000A034BF0D00180A78BB91D737C0B0C2E58C6F2931C00000000000000840
558	\N	\N	\N	\N	01010000A034BF0D00FC6B4EE547FD38C0C8AD8339E6C72BC00000000000000840
559	\N	\N	\N	\N	01010000A034BF0D00309F81187B303AC0608DBFFA29042CC00000000000000840
560	\N	\N	\N	\N	01010000A034BF0D000C429E7125563BC07C819F5D7B2931C00000000000000840
561	\N	\N	\N	\N	01010000A034BF0D00309F81187B303AC0C8AD8339E6C72BC00000000000000840
562	\N	\N	\N	\N	01010000A034BF0D004856D4771B3C3DC0D842A7C82A9F2AC00000000000000840
563	\N	\N	\N	\N	01010000A034BF0D00DC7961E1080A3FC0CCEBA462E22931C00000000000000840
564	\N	\N	\N	\N	01010000A034BF0D00780EFEF8BF223DC0D842A7C82A9F2AC00000000000000840
565	\N	\N	\N	\N	01010000A034BF0D00F45BF6C287593BC058FCC28A664523C00000000000000840
566	\N	\N	\N	\N	01010000A034BF0D0094A7D685D1EA3BC090E27A6BA9D317C00000000000000840
567	\N	\N	\N	\N	01010000A034BF0D00F45BF6C287593BC0A03A7185218023C00000000000000840
568	\N	\N	\N	\N	01010000A034BF0D00A28CEF4DD9CA40C0D0BB70247F5128C00000000000000840
569	\N	\N	\N	\N	01010000A034BF0D00720A1B4CD93A41C078A947790E942BC00000000000000840
570	\N	\N	\N	\N	01010000A034BF0D00A28CEF4DD9CA40C01866A2BED11928C00000000000000840
571	\N	\N	\N	\N	01010000A034BF0D00E8F91B995E4441C0D81530EDE72831C00000000000000840
572	\N	\N	\N	\N	01010000A034BF0D00A46DE562C63742C02893DB4C143F2AC00000000000000840
573	\N	\N	\N	\N	01010000A034BF0D00DA795919FE1E43C0D0F470F0612A31C00000000000000840
574	\N	\N	\N	\N	01010000A034BF0D00B81B2D44412C42C02893DB4C143F2AC00000000000000840
575	\N	\N	\N	\N	01010000A034BF0D0050B5C6DDDAC545C01097699D8F9B2AC00000000000000840
576	\N	\N	\N	\N	01010000A034BF0D002AE29E425CDE44C0B082D8B9EF2A31C00000000000000840
577	\N	\N	\N	\N	01010000A034BF0D003C077FFC5FD145C01097699D8F9B2AC00000000000000840
578	\N	\N	\N	\N	01010000A034BF0D00EADD226D9D4B47C0C8AB17E570162CC00000000000000840
579	\N	\N	\N	\N	01010000A034BF0D0032B942B399B846C0544010F1652A31C00000000000000840
580	\N	\N	\N	\N	01010000A034BF0D00EADD226D9D4B47C0E8326F8B9EE62BC00000000000000840
581	\N	\N	\N	\N	01010000A034BF0D008277BC0637E547C0C8AB17E570162CC00000000000000840
582	\N	\N	\N	\N	01010000A034BF0D00B60B1BDCF57748C0CC6213BAEF2A31C00000000000000840
583	\N	\N	\N	\N	01010000A034BF0D008277BC0637E547C0E8326F8B9EE62BC00000000000000840
584	\N	\N	\N	\N	01010000A034BF0D00FA74D8DA927948C058FCC28A664523C00000000000000840
585	\N	\N	\N	\N	01010000A034BF0D00FE5F79CA37C248C01072AF248BCE17C00000000000000840
586	\N	\N	\N	\N	01010000A034BF0D00FA74D8DA927948C0A03A7185218023C00000000000000840
587	\N	\N	\N	\N	01010000A034BF0D002A89E0F291DC4AC0D0BD17BE18AB2AC00000000000000840
588	\N	\N	\N	\N	01010000A034BF0D001A4A73B5BFE44AC0C8AB17E570162CC00000000000000840
589	\N	\N	\N	\N	01010000A034BF0D00BEA46EA426E54AC0A0871164DBF22CC00000000000000840
590	\N	\N	\N	\N	01010000A034BF0D001A4A73B5BFE44AC0E8326F8B9EE62BC00000000000000840
591	\N	\N	\N	\N	01010000A034BF0D00C2E2BE4C33524AC03460D5F0652A31C00000000000000840
592	\N	\N	\N	\N	01010000A034BF0D00BA3B6FDAEBE64AC0B8C17D9E49EC2CC00000000000000840
593	\N	\N	\N	\N	01010000A034BF0D00A26DE562C6374BC0D0BD17BE18AB2AC00000000000000840
594	\N	\N	\N	\N	01010000A034BF0D00762D136861FE4BC0C84562183B792BC00000000000000840
595	\N	\N	\N	\N	01010000A034BF0D0072663666732B4BC0D0BD17BE18AB2AC00000000000000840
596	\N	\N	\N	\N	01010000A034BF0D005AFB95758F114CC0B4B650BAEF2A31C00000000000000840
597	\N	\N	\N	\N	01010000A034BF0D00AA55D6EE867B4CC0F05578E257212AC00000000000000840
598	\N	\N	\N	\N	01010000A034BF0D002230B0040C4E4AC058FCC28A664523C00000000000000840
599	\N	\N	\N	\N	01010000A034BF0D009A8F1D7EF9074AC0303E9B6BBAAF17C00000000000000840
600	\N	\N	\N	\N	01010000A034BF0D002230B0040C4E4AC0A03A7185218023C00000000000000840
601	\N	\N	\N	\N	01010000A034BF0D0076BF72FA34EA4AC030FCC28A664523C00000000000000840
602	\N	\N	\N	\N	01010000A034BF0D001EEC2CE1E2314BC020EE8F8B1AA817C00000000000000840
603	\N	\N	\N	\N	01010000A034BF0D0076BF72FA34EA4AC0A03A7185218023C00000000000000840
604	\N	\N	\N	\N	01010000A034BF0D00F6B180612A134CC058FCC28A664523C00000000000000840
605	\N	\N	\N	\N	01010000A034BF0D0082157E5AD05B4CC030A5A91DDBAF17C00000000000000840
606	\N	\N	\N	\N	01010000A034BF0D00F6B180612A134CC0A03A7185218023C00000000000000840
607	\N	\N	\N	\N	01010000A034BF0D00729D11BACC3A4DC0087A062202F128C00000000000000840
608	\N	\N	\N	\N	01010000A034BF0D008E0842B888974DC078166ED7EE912FC00000000000000840
609	\N	\N	\N	\N	01010000A034BF0D000A67A82029584DC0B0DD0EA2B14730C00000000000000840
610	\N	\N	\N	\N	01010000A034BF0D0022E5763D5CDB4DC0FC31A1C8A35030C00000000000000840
611	\N	\N	\N	\N	01010000A034BF0D00005EA33F689E22C0108FFE4D940F2DC00000000000000840
612	\N	\N	\N	\N	01010000A034BF0D00F87D8A907CF124C05807A30C40F631C00000000000000840
613	\N	\N	\N	\N	01010000A034BF0D003B548F320E5451C088FDF44BA63D2DC00000000000000840
614	\N	\N	\N	\N	01010000A034BF0D0089855B35799E51C044E93BEB08DE31C00000000000000840
\.


--
-- Data for Name: first_floor_edges; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.first_floor_edges (level, _area_id, _length, _id, source, target, geom, f_zlev, t_zlev) FROM stdin;
first_floor	\N	0.124150509797004815	254	254	252	01020000A034BF0D00020000004E6DE562C6E74AC0289D3316882B28C09A9999999999E93F4E6DE562C6E74AC068550ABE186B28C09A9999999999E93F	\N	\N
second_floor	\N	0.249999999999488409	497	498	496	01020000A034BF0D0002000000105FA33F685E20C0EC12A61DAB9433C00000000000000840F05DA33F68DE20C0EC12A61DAB9433C00000000000000840	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035084216	3	1	2	01020000A034BF0D0003000000CCC6C444F70B3FC0283B51E7C38123C09A9999999999E93FCCC6C444F70B3FC0186282EF6F9E24C09A9999999999E93FC4C1243DDC6F3EC0286CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	\N	0.10867074331861204	4	3	1	01020000A034BF0D0002000000CCC6C444F70B3FC0680F4036204A23C09A9999999999E93FCCC6C444F70B3FC0283B51E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NB	5.5092697945310567	5	4	3	01020000A034BF0D000B00000000714B1FBF8C3FC0807E2ADAF67913C09A9999999999E93F0CFA8EA456763EC0505A1CC598D317C09A9999999999E93F0CFA8EA456763EC030870C00904218C09A9999999999E93F6487B2FCA8693EC0D0517E9F467518C09A9999999999E93F6487B2FCA8693EC0D0DD39D6DFE11FC09A9999999999E93F90152BD57D893EC0400B0E9C993020C09A9999999999E93F90152BD57D893EC0D862246FBA3121C09A9999999999E93F948FB2FCA8093FC0E85633BE103222C09A9999999999E93F948FB2FCA8093FC0189C803B7E7622C09A9999999999E93FCCC6C444F70B3FC0800AA5CB1A7B22C09A9999999999E93FCCC6C444F70B3FC0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.48042511641065744	6	2	5	01020000A034BF0D0002000000C4C1243DDC6F3EC0286CC2FEA5D625C09A9999999999E93F9C983119DFF43BC0386CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6N6	3.96763137403211941	7	6	7	01020000A034BF0D000A0000009C939111C4583BC0680F4036204A23C09A9999999999E93F9C939111C4583BC0780AA5CB1A7B22C09A9999999999E93FFC7637AD88593BC0B8435994917922C09A9999999999E93FFC7637AD88593BC038AF5A65FD2E22C09A9999999999E93F4C36644ED4D73BC0A0300123663221C09A9999999999E93F4C36644ED4D73BC008D9EA4F453120C09A9999999999E93F20A8EB75FFF73BC0C0EAB701DEE11FC09A9999999999E93F20A8EB75FFF73BC0E0440074487518C09A9999999999E93F2C812E8413EB3BC010A90BAD984118C09A9999999999E93F2C812E8413EB3BC0307C1B72A1D217C09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318697305	8	8	6	01020000A034BF0D00020000009C939111C4583BC0583B51E7C38123C09A9999999999E93F9C939111C4583BC0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035078176	9	5	8	01020000A034BF0D00030000009C983119DFF43BC0386CC2FEA5D625C09A9999999999E93F9C939111C4583BC0486282EF6F9E24C09A9999999999E93F9C939111C4583BC0583B51E7C38123C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.20000000000002882	10	5	9	01020000A034BF0D00030000009C983119DFF43BC0386CC2FEA5D625C09A9999999999E93F94983119DFF43BC0486CC2FEA5D625C09A9999999999E93F6465FEE5ABC13AC0486CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6N5	3.93373895941855523	11	10	11	01020000A034BF0D000600000068605EDE90253AC0F80D4036204A23C09A9999999999E93F68605EDE90253AC0800AA5CB1A7B22C09A9999999999E93FE47CB842CC243AC078435994917922C09A9999999999E93FE47CB842CC243AC010AE5A65FD2E22C09A9999999999E93FB02CD7C7B79639C0A80D986FD41221C09A9999999999E93FB02CD7C7B79639C05092C401C8C417C09A9999999999E93F	\N	\N
first_floor	\N	0.108670743319379426	12	12	10	01020000A034BF0D000200000068605EDE90253AC0683B51E7C38123C09A9999999999E93F68605EDE90253AC0F80D4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035076755	13	9	12	01020000A034BF0D00030000006465FEE5ABC13AC0486CC2FEA5D625C09A9999999999E93F68605EDE90253AC0506282EF6F9E24C09A9999999999E93F68605EDE90253AC0683B51E7C38123C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.610236572961170509	14	9	13	01020000A034BF0D00030000006465FEE5ABC13AC0486CC2FEA5D625C09A9999999999E93F6065FEE5ABC13AC0486CC2FEA5D625C09A9999999999E93F68B4326F73253AC0486CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.15999999999998238	15	13	14	01020000A034BF0D000200000068B4326F73253AC0486CC2FEA5D625C09A9999999999E93F4458A3AC7DFC38C0506CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.545763427053998385	16	14	15	01020000A034BF0D00020000004458A3AC7DFC38C0506CC2FEA5D625C09A9999999999E93F84CBBC85C67038C0506CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6N0	3.96745883010850342	17	16	17	01020000A034BF0D000A00000094C61C7EABD437C0680F4036204A23C09A9999999999E93F94C61C7EABD437C0800AA5CB1A7B22C09A9999999999E93F5CE376E2E6D337C008445994917922C09A9999999999E93F5CE376E2E6D337C0E8AE5A65FD2E22C09A9999999999E93FCC9CAF4DC65537C0D021CC3BBC3221C09A9999999999E93FCC9CAF4DC65537C0386A0231423120C09A9999999999E93FAC41312CF33537C0F0670BDC37E31FC09A9999999999E93FAC41312CF33537C0308B10519E7218C09A9999999999E93F40084BD4A04237C0E070A9B0E73F18C09A9999999999E93F40084BD4A04237C080C0EE4E8ED117C09A9999999999E93F	\N	\N
first_floor	\N	0.10867074331878257	18	18	16	01020000A034BF0D000200000094C61C7EABD437C0883B51E7C38123C09A9999999999E93F94C61C7EABD437C0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035071559	19	15	18	01020000A034BF0D000300000084CBBC85C67038C0506CC2FEA5D625C09A9999999999E93F94C61C7EABD437C0806282EF6F9E24C09A9999999999E93F94C61C7EABD437C0883B51E7C38123C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.70000000000005969	20	15	19	01020000A034BF0D000300000084CBBC85C67038C0506CC2FEA5D625C09A9999999999E93F84CBBC85C67038C0586CC2FEA5D625C09A9999999999E93F4498895293BD35C0606CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NV	3.28707853436293451	21	20	21	01020000A034BF0D00050000005C93E94A782135C0680F4036204A23C09A9999999999E93F5C93E94A782135C078E80E2E742D22C09A9999999999E93F5C93E94A782135C0501D5B5E1B2C22C09A9999999999E93F88139A62CA7B33C0503B781B7FC11DC09A9999999999E93F88139A62CA7B33C0A0767CC5F1281CC09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318839413	22	22	20	01020000A034BF0D00020000005C93E94A782135C0A83B51E7C38123C09A9999999999E93F5C93E94A782135C0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035067119	23	19	22	01020000A034BF0D00030000004498895293BD35C0606CC2FEA5D625C09A9999999999E93F5C93E94A782135C0986282EF6F9E24C09A9999999999E93F5C93E94A782135C0A83B51E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NV	0.223892632226773969	24	21	23	01020000A034BF0D000300000088139A62CA7B33C0A0767CC5F1281CC09A9999999999E93FD8088D3A178933C060A1B065BEF31BC09A9999999999E93F88AC901499AF33C060A1B065BEF31BC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NV	0.17715025427540898	25	23	24	01020000A034BF0D000300000088AC901499AF33C060A1B065BEF31BC09A9999999999E93F9402C84064BD33C090F98D16EB2A1CC09A9999999999E93FA4A8C7233CD733C090F98D16EB2A1CC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NV	0.611457521901398238	26	23	25	01020000A034BF0D000300000088AC901499AF33C060A1B065BEF31BC09A9999999999E93FE0F5E5E5601D34C0007C5B209F3C1AC09A9999999999E93FE0F5E5E5601D34C010E4096880371AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NV	1.65995516342792482	27	21	26	01020000A034BF0D000200000088139A62CA7B33C0A0767CC5F1281CC09A9999999999E93FD0CE647C4E4F32C0C063A72C027717C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.73423657294600275	28	19	27	01020000A034BF0D00030000004498895293BD35C0606CC2FEA5D625C09A9999999999E93F4498895293BD35C0686CC2FEA5D625C09A9999999999E93FC043F5649C0133C0786CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.21999999999999886	29	27	28	01020000A034BF0D0002000000C043F5649C0133C0786CC2FEA5D625C09A9999999999E93F082570794AC931C0786CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.548763863374944094	30	28	29	01020000A034BF0D0002000000082570794AC931C0786CC2FEA5D625C09A9999999999E93F00B991AFCE3C31C0806CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NQ	3.96668080187922589	31	30	31	01020000A034BF0D000B00000024B4F1A7B3A030C0680F4036204A23C09A9999999999E93F24B4F1A7B3A030C0900AA5CB1A7B22C09A9999999999E93FDCD04B0CEF9F30C008445994917922C09A9999999999E93FDCD04B0CEF9F30C008AF5A65FD2E22C09A9999999999E93FEC65A2B3653530C020D907B4EA5921C09A9999999999E93FEC65A2B3653530C070089905205820C09A9999999999E93F00C3F0B9E00230C030856B242CE61FC09A9999999999E93F00C3F0B9E00230C0E0D47EF7372A1CC09A9999999999E93F00C3F0B9E00230C0B0D2CF2E5D6E18C09A9999999999E93F1C51D44F0B0F30C0409A41D7B23D18C09A9999999999E93F1C51D44F0B0F30C0F0521D0805D017C09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318938889	32	32	30	01020000A034BF0D000200000024B4F1A7B3A030C0E03B51E7C38123C09A9999999999E93F24B4F1A7B3A030C0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035061523	33	29	32	01020000A034BF0D000300000000B991AFCE3C31C0806CC2FEA5D625C09A9999999999E93F24B4F1A7B3A030C0D86282EF6F9E24C09A9999999999E93F24B4F1A7B3A030C0E03B51E7C38123C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	4.50285834674909236	34	29	33	01020000A034BF0D000400000000B991AFCE3C31C0806CC2FEA5D625C09A9999999999E93FFCB891AFCE3C31C0806CC2FEA5D625C09A9999999999E93FA089D96DE5D329C0A06CC2FEA5D625C09A9999999999E93F88D2CCD1059329C080B5B562C69525C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.15323592294051025	35	33	34	01020000A034BF0D000200000088D2CCD1059329C080B5B562C69525C09A9999999999E93F609E71E1904427C080B5B562C69525C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.81419711436426168	36	34	35	01020000A034BF0D0003000000609E71E1904427C080B5B562C69525C09A9999999999E93F4022306DFA9B26C080B5B562C69525C09A9999999999E93FB08896D3608224C0184F4FFC5FAF27C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	3.30212362160598616	37	35	36	01020000A034BF0D0002000000B08896D3608224C0184F4FFC5FAF27C09A9999999999E93F107B24C261CF1BC0184F4FFC5FAF27C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	10.1815012466548538	38	36	37	01020000A034BF0D0003000000107B24C261CF1BC0184F4FFC5FAF27C09A9999999999E93FB0AB285BDEA319C07067D1489E9926C09A9999999999E93FB0AB285BDEA319C0407B8399F92BFEBF9A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.0403556115579419838	39	37	38	01020000A034BF0D0002000000B0AB285BDEA319C0407B8399F92BFEBF9A9999999999E93FB0AB285BDEA319C0C0DB85ACAD86FDBF9A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.0453804721045685255	40	38	39	01020000A034BF0D0002000000B0AB285BDEA319C0C0DB85ACAD86FDBF9A9999999999E93FB0AB285BDEA319C0C0CCCCCCCCCCFCBF9A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kU	3.28566286245995709	41	40	41	01020000A034BF0D00050000006079F527AB7011C0C0DB85ACAD86FDBF9A9999999999E93F4061FDD216AC0FC0C0DB85ACAD86FDBF9A9999999999E93FA01447DF18D70EC0C0DB85ACAD86FDBF9A9999999999E93F808F772C8C7A0AC080D1E64694CDF4BF9A9999999999E93F00C3E64694CDF4BF80D1E64694CDF4BF9A9999999999E93F	\N	\N
first_floor	\N	0.249999999999801048	42	42	40	01020000A034BF0D00020000008078F527AB7012C0C0DB85ACAD86FDBF9A9999999999E93F6079F527AB7011C0C0DB85ACAD86FDBF9A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.79999999999999716	43	38	42	01020000A034BF0D0003000000B0AB285BDEA319C0C0DB85ACAD86FDBF9A9999999999E93F30416CE64A0B14C0C0DB85ACAD86FDBF9A9999999999E93F8078F527AB7012C0C0DB85ACAD86FDBF9A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kT	3.35773400212494488	44	43	44	01020000A034BF0D0007000000F05DA33F68DE20C0407B8399F92BFEBF9A9999999999E93F48C2DE1EB8AB21C0407B8399F92BFEBF9A9999999999E93FB0A684BA7CCC21C0407B8399F92BFEBF9A9999999999E93F48A3049220FD22C0C09683DDDAA6F4BF9A9999999999E93F90438D362AB326C0C09683DDDAA6F4BF9A9999999999E93F509860EFAACC26C080F0E816D5DAF3BF9A9999999999E93F1079B440D10C27C080F0E816D5DAF3BF9A9999999999E93F	\N	\N
first_floor	\N	0.224361194929997509	45	45	43	01020000A034BF0D000200000070EF2DC7886B20C0407B8399F92BFEBF9A9999999999E93FF05DA33F68DE20C0407B8399F92BFEBF9A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.79999999999999716	46	37	45	01020000A034BF0D0003000000B0AB285BDEA319C0407B8399F92BFEBF9A9999999999E93F2016E5CF713C1FC0407B8399F92BFEBF9A9999999999E93F70EF2DC7886B20C0407B8399F92BFEBF9A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.7728613987631876	47	36	46	01020000A034BF0D0003000000107B24C261CF1BC0184F4FFC5FAF27C09A9999999999E93F70DE9C754ABA1BC0681D93A2EBB927C09A9999999999E93F80B4213EB5C014C0681D93A2EBB927C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	8.28662460373652721	48	46	47	01020000A034BF0D000A00000080B4213EB5C014C0681D93A2EBB927C09A9999999999E93F6025AB707C7704C0681D93A2EBB927C09A9999999999E93F80BB3BE9B35904C0F042B78079B227C09A9999999999E93FC04AFEDEDCB503C0F042B78079B227C09A9999999999E93F00516A098377F9BF70FA24AAF2F325C09A9999999999E93F00E041007F77BDBFF035E889C6EF25C09A9999999999E93F00DF4C185D17E53F40E462BA616324C09A9999999999E93F00DF4C185D17E53F680249B66DA721C09A9999999999E93F000FDD6C5825E93F68FFFF008E6621C09A9999999999E93F000FDD6C5825E93F28897F828FFD20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	1.42077893475734118	49	48	49	01020000A034BF0D00040000000010C12DEE49CFBF28897F828FFD20C09A9999999999E93F0023C0181341E6BF28897F828FFD20C09A9999999999E93F402BE47CB0A0F0BF28897F828FFD20C09A9999999999E93F40BDD35CC1B5F7BFE8968166ED1A20C09A9999999999E93F	\N	\N
first_floor	\N	0.250669824930980667	50	50	48	01020000A034BF0D00020000000000A10A9780793F28897F828FFD20C09A9999999999E93F0010C12DEE49CFBF28897F828FFD20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.77958261739550494	51	47	50	01020000A034BF0D0003000000000FDD6C5825E93F28897F828FFD20C09A9999999999E93F0043CA763143DD3F28897F828FFD20C09A9999999999E93F0000A10A9780793F28897F828FFD20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	1.64072386883400156	52	49	51	01020000A034BF0D000200000040BDD35CC1B5F7BFE8968166ED1A20C09A9999999999E93F80235D8414FB08C0E8968166ED1A20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	0.833029560556820092	53	49	52	01020000A034BF0D000300000040BDD35CC1B5F7BFE8968166ED1A20C09A9999999999E93F80F5B51E2CD5F0BFF0BB7B7DB57D1EC09A9999999999E93F80F5B51E2CD5F0BFE088E89125971DC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	1.78292440942558983	54	52	53	01020000A034BF0D000400000080F5B51E2CD5F0BFE088E89125971DC09A9999999999E93FC03593FF666FF2BFD038B1D996301DC09A9999999999E93FC03593FF666FF2BF802C0BADBDAB17C09A9999999999E93F00172739EF64F5BF4034A69E5BEE16C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	0.4276658036609291	55	53	54	01020000A034BF0D000200000000172739EF64F5BF4034A69E5BEE16C09A9999999999E93FC08C2C52A73CFCBF4034A69E5BEE16C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	1.04999999600188687	56	54	55	01020000A034BF0D0003000000C08C2C52A73CFCBF4034A69E5BEE16C09A9999999999E93FC0CA04DC865102C04034A69E5BEE16C09A9999999999E93F004DF30EBA8406C04034A69E5BEE16C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048k2	0.954043667811909302	57	56	57	01020000A034BF0D00050000008060E6C8A14C0FC0208876BC630013C09A9999999999E93F8060E6C8A14C0FC060BFFFFDC36511C09A9999999999E93F8060E6C8A14C0FC0803FF478093611C09A9999999999E93F40A9C743B6FA0EC0E0E364B6130D11C09A9999999999E93F40A9C743B6FA0EC080A98C83D4800EC09A9999999999E93F	\N	\N
first_floor	\N	0.0899999999999323563	58	58	56	01020000A034BF0D00020000008060E6C8A14C0FC0301739B28C5C13C09A9999999999E93F8060E6C8A14C0FC0208876BC630013C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	1.72945421111938025	59	55	58	01020000A034BF0D0006000000004DF30EBA8406C04034A69E5BEE16C09A9999999999E93F40D2E141EDB70AC04034A69E5BEE16C09A9999999999E93FE0B61077B8BD0BC04034A69E5BEE16C09A9999999999E93F8060E6C8A14C0FC0705FBBF5E62615C09A9999999999E93F8060E6C8A14C0FC0F0DFAF702CF714C09A9999999999E93F8060E6C8A14C0FC0301739B28C5C13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048k1	0.945085081031279639	60	59	60	01020000A034BF0D0005000000004DF30EBA8406C0208876BC630013C09A9999999999E93F004DF30EBA8406C060BFFFFDC36511C09A9999999999E93F004DF30EBA8406C0008FE09DDE1411C09A9999999999E93F804EF30EBA8406C0408EE09DDE1411C09A9999999999E93F804EF30EBA8406C0C05495B43E710EC09A9999999999E93F	\N	\N
first_floor	\N	0.0899999999999323563	61	61	59	01020000A034BF0D0002000000004DF30EBA8406C0301739B28C5C13C09A9999999999E93F004DF30EBA8406C0208876BC630013C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	0.892390913162003585	62	55	61	01020000A034BF0D0003000000004DF30EBA8406C04034A69E5BEE16C09A9999999999E93F004DF30EBA8406C0F0DFAF702CF714C09A9999999999E93F004DF30EBA8406C0301739B28C5C13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048k4	0.94508508103123845	63	62	63	01020000A034BF0D0005000000C08C2C52A73CFCBF208876BC630013C09A9999999999E93FC08C2C52A73CFCBF60BFFFFDC36511C09A9999999999E93FC08C2C52A73CFCBF908EE09DDE1411C09A9999999999E93F008E2C52A73CFCBF408EE09DDE1411C09A9999999999E93F008E2C52A73CFCBFC05495B43E710EC09A9999999999E93F	\N	\N
first_floor	\N	0.0899999999999323563	64	64	62	01020000A034BF0D0002000000C08C2C52A73CFCBF301739B28C5C13C09A9999999999E93FC08C2C52A73CFCBF208876BC630013C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	0.892390913162003585	65	54	64	01020000A034BF0D0003000000C08C2C52A73CFCBF4034A69E5BEE16C09A9999999999E93FC08C2C52A73CFCBFF0DFAF702CF714C09A9999999999E93FC08C2C52A73CFCBF301739B28C5C13C09A9999999999E93F	\N	\N
first_floor	\N	0.0429537524212110847	66	65	66	01020000A034BF0D000300000000B15DBEEEBAE8BF301739B28C5C13C09A9999999999E93F00B15DBEEEBAE8BF604FF6650A5913C09A9999999999E93F0092B9B7F7D5E7BF80CB21856B3C13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	1.12614127079994719	67	53	65	01020000A034BF0D000600000000172739EF64F5BF4034A69E5BEE16C09A9999999999E93F00864FEC40D6F3BF1050700BB08A16C09A9999999999E93F808E2A5D2E73E9BF60C0019C85C314C09A9999999999E93F808E2A5D2E73E9BFD0E0F8B5A13214C09A9999999999E93F00B15DBEEEBAE8BF20451FC2991B14C09A9999999999E93F00B15DBEEEBAE8BF301739B28C5C13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kR	0.961965972508309508	68	67	68	01020000A034BF0D00050000000092B9B7F7D5E7BF208876BC630013C09A9999999999E93F0092B9B7F7D5E7BF60BFFFFDC36511C09A9999999999E93F0092B9B7F7D5E7BFE01F3BF3A63311C09A9999999999E93F007834CCA51DE7BFA07CCAB59C1C11C09A9999999999E93F007834CCA51DE7BF0078C184C2610EC09A9999999999E93F	\N	\N
first_floor	\N	0.0586234430819274621	69	66	67	01020000A034BF0D00020000000092B9B7F7D5E7BF80CB21856B3C13C09A9999999999E93F0092B9B7F7D5E7BF208876BC630013C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	0.355302154765635703	70	69	70	01020000A034BF0D00030000008034FF4EEED4E6BF301739B28C5C13C09A9999999999E93F00408109F4EAE0BFB0D5E8FACB1914C09A9999999999E93F002DA4B8CFD2DBBFB0D5E8FACB1914C09A9999999999E93F	\N	\N
first_floor	\N	0.0443731523340138781	71	66	69	01020000A034BF0D00020000000092B9B7F7D5E7BF80CB21856B3C13C09A9999999999E93F8034FF4EEED4E6BF301739B28C5C13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kF	0.512835680985825326	72	52	71	01020000A034BF0D000200000080F5B51E2CD5F0BFE088E89125971DC09A9999999999E93F8003FADFAE0FE6BFF04B3A66D0231CC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.674423778852499822	73	47	72	01020000A034BF0D0002000000000FDD6C5825E93F28897F828FFD20C09A9999999999E93F000FDD6C5825E93F80CE57DF82481FC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048ky	3.92624478699333057	74	73	74	01020000A034BF0D000500000080B4213EB5C014C0409C1657F7752CC09A9999999999E93F80B4213EB5C014C028C3475FA3922DC09A9999999999E93F80B4213EB5C014C050CE498A2AA92DC09A9999999999E93F400781AB8F8B19C0D8BB7CE04B0730C09A9999999999E93F400781AB8F8B19C0FC189D930EA931C09A9999999999E93F	\N	\N
first_floor	\N	0.0453800465674589759	75	75	73	01020000A034BF0D000200000080B4213EB5C014C060D06649BB5E2CC09A9999999999E93F80B4213EB5C014C0409C1657F7752CC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.32189675649850358	76	46	75	01020000A034BF0D000300000080B4213EB5C014C0681D93A2EBB927C09A9999999999E93F80B4213EB5C014C078A935410F422BC09A9999999999E93F80B4213EB5C014C060D06649BB5E2CC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048ky	1.92035734862469099	77	74	76	01020000A034BF0D0002000000400781AB8F8B19C0FC189D930EA931C09A9999999999E93F400781AB8F8B19C0EC12A61DAB9433C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048ky	1.72678156895655377	78	76	77	01020000A034BF0D0002000000400781AB8F8B19C0EC12A61DAB9433C09A9999999999E93F400781AB8F8B19C0F0130479B94E35C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048ks	3.29808014868064747	79	78	79	01020000A034BF0D0009000000404EBBD74E5A11C060E0DABC1EB735C09A9999999999E93F000B89325E7F0FC060E0DABC1EB735C09A9999999999E93F2022620156D30EC060E0DABC1EB735C09A9999999999E93FC0379EEF77860AC0AC5D137FBA4036C09A9999999999E93FE0398EFBAF8608C0AC5D137FBA4036C09A9999999999E93F0010EE36EA6208C0EC62A737334536C09A9999999999E93FC0D782B56DC6F8BFEC62A737334536C09A9999999999E93FC01D7E3B0B74F8BF501707100D4036C09A9999999999E93F001E7E3B0B74F4BF501707100D4036C09A9999999999E93F	\N	\N
first_floor	\N	0.250000000000483169	80	80	78	01020000A034BF0D00020000006050BBD74E5A12C060E0DABC1EB735C09A9999999999E93F404EBBD74E5A11C060E0DABC1EB735C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048ky	1.96701315350947659	81	77	80	01020000A034BF0D0004000000400781AB8F8B19C0F0130479B94E35C09A9999999999E93F80D5259CFAE917C060E0DABC1EB735C09A9999999999E93F20193296EEF413C060E0DABC1EB735C09A9999999999E93F6050BBD74E5A12C060E0DABC1EB735C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048k8	1.27613336202121364	82	81	82	01020000A034BF0D0004000000F05DA33F68DE20C09CD0749DE5AC35C09A9999999999E93F48C2DE1EB8AB21C09CD0749DE5AC35C09A9999999999E93F20243411B0CE21C09CD0749DE5AC35C09A9999999999E93F308A991BCBF222C0A483A722F33E36C09A9999999999E93F	\N	\N
first_floor	\N	0.249999999999488409	83	83	81	01020000A034BF0D0002000000105FA33F685E20C09CD0749DE5AC35C09A9999999999E93FF05DA33F68DE20C09CD0749DE5AC35C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048ky	1.95047189837529489	84	77	83	01020000A034BF0D0004000000400781AB8F8B19C0F0130479B94E35C09A9999999999E93FF0F9433D40041BC09CD0749DE5AC35C09A9999999999E93F60F5CFC030221FC09CD0749DE5AC35C09A9999999999E93F105FA33F685E20C09CD0749DE5AC35C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048k8	2.02896715623166379	85	82	84	01020000A034BF0D0006000000308A991BCBF222C0A483A722F33E36C09A9999999999E93F28CE986A3C7223C0A483A722F33E36C09A9999999999E93F488ADD50167623C0ACE1C915E04036C09A9999999999E93FF097B627E37826C0ACE1C915E04036C09A9999999999E93FF8CABD00F07D26C0244846A9593E36C09A9999999999E93FF8CABD00F0FD26C0244846A9593E36C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048k8	1.21357020913911451	86	82	85	01020000A034BF0D0002000000308A991BCBF222C0A483A722F33E36C09A9999999999E93F78B7711D6F3B21C0FC6CBB21A11A37C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kr	3.52797968789575611	87	86	87	01020000A034BF0D0007000000F05DA33F68DE20C0EC12A61DAB9433C09A9999999999E93F50C2DE1EB8AB21C0EC12A61DAB9433C09A9999999999E93FF8B832025EC721C0EC12A61DAB9433C09A9999999999E93F9051437018B822C0385FAE54080D34C09A9999999999E93FE08CC814B4EA26C0385FAE54080D34C09A9999999999E93F18418B45642427C054B90F6DE02934C09A9999999999E93FD84014EA1F7127C054B90F6DE02934C09A9999999999E93F	\N	\N
first_floor	\N	0.249999999999488409	88	88	86	01020000A034BF0D0002000000105FA33F685E20C0EC12A61DAB9433C09A9999999999E93FF05DA33F68DE20C0EC12A61DAB9433C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048ky	1.79809885877850206	89	76	88	01020000A034BF0D0003000000400781AB8F8B19C0EC12A61DAB9433C09A9999999999E93F60F5CFC030221FC0EC12A61DAB9433C09A9999999999E93F105FA33F685E20C0EC12A61DAB9433C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kp	2.52805892473377458	90	89	90	01020000A034BF0D0004000000404EBBD74E5A11C0FC189D930EA931C09A9999999999E93FC000B28EED410EC0FC189D930EA931C09A9999999999E93F80FA057293DD0DC0FC189D930EA931C09A9999999999E93F40C6E66CB0FC02C084FF40F42A0533C09A9999999999E93F	\N	\N
first_floor	\N	0.250000000000483169	91	91	89	01020000A034BF0D00020000006050BBD74E5A12C0FC189D930EA931C09A9999999999E93F404EBBD74E5A11C0FC189D930EA931C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048ky	1.79809885877850206	92	74	91	01020000A034BF0D0003000000400781AB8F8B19C0FC189D930EA931C09A9999999999E93F409E1DE8A69314C0FC189D930EA931C09A9999999999E93F6050BBD74E5A12C0FC189D930EA931C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kp	1.79483799915185571	93	90	92	01020000A034BF0D000400000040C6E66CB0FC02C084FF40F42A0533C09A9999999999E93F40C6E66CB0FC02C0B44118D7160933C09A9999999999E93F40B184E4298AF3BF64CF6C460A3034C09A9999999999E93F808B683C3A23F1BF64CF6C460A3034C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kp	1.51190153495346058	94	90	93	01020000A034BF0D000300000040C6E66CB0FC02C084FF40F42A0533C09A9999999999E93F80CCB0601C18F5BF8433AFAC16F731C09A9999999999E93F4094A3A68EC6F4BF8433AFAC16F731C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kp	1.37349253673596339	95	93	94	01020000A034BF0D00040000004094A3A68EC6F4BF8433AFAC16F731C09A9999999999E93F8039967AA6F3E5BF10AC19F64A5A31C09A9999999999E93F00EA7F2C6B27E1BF10AC19F64A5A31C09A9999999999E93F000E219E8222D2BFFC302EA7991931C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kp	0.692126494316682606	96	93	95	01020000A034BF0D00030000004094A3A68EC6F4BF8433AFAC16F731C09A9999999999E93F800ABFD434D6ECBF747473F0CD5C32C09A9999999999E93F802FA1F870ABE8BF747473F0CD5C32C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.985541604671849925	97	35	96	01020000A034BF0D0003000000B08896D3608224C0184F4FFC5FAF27C09A9999999999E93F78D5128EF50D25C0E89BCBB6F43A28C09A9999999999E93F78D5128EF50D25C018CFFEE9276E29C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.63552649702931951	98	33	97	01020000A034BF0D000500000088D2CCD1059329C080B5B562C69525C09A9999999999E93FD07F018698DF2AC0380881AE334924C09A9999999999E93FD07F018698DF2AC008686E4EFB9E21C09A9999999999E93F10DF512003302BC0C8081EB4904E21C09A9999999999E93F10DF512003302BC010E0328373FB20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.649886544078981387	99	97	98	01020000A034BF0D000200000010DF512003302BC010E0328373FB20C09A9999999999E93F10DF512003302BC02008B22A6B5D1FC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	1.58093973909596341	100	99	100	01020000A034BF0D0005000000406DC0E3AC1129C010E0328373FB20C09A9999999999E93FE8387EC2D42A28C010E0328373FB20C09A9999999999E93F70F689038ED127C0E08AD0B2B25421C09A9999999999E93F78C44D3B84D127C0E08AD0B2B25421C09A9999999999E93F906BECE3AC9126C0F8316F5BDB1420C09A9999999999E93F	\N	\N
first_floor	\N	0.259251683000996991	101	101	99	01020000A034BF0D00020000007045B886699629C010E0328373FB20C09A9999999999E93F406DC0E3AC1129C010E0328373FB20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.800000000000011369	102	97	101	01020000A034BF0D000300000010DF512003302BC010E0328373FB20C09A9999999999E93F68438DFF527D2AC010E0328373FB20C09A9999999999E93F7045B886699629C010E0328373FB20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	0.976126239503715909	103	100	102	01020000A034BF0D0003000000906BECE3AC9126C0F8316F5BDB1420C09A9999999999E93F686694701B7827C0306E8E9DD95C1EC09A9999999999E93F686694701B7827C0906DDB720E011DC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	141	141	139	01020000A034BF0D000200000068B4326F73253AC0289D3316882B28C09A9999999999E93F68B4326F73253AC068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	1.00397283951121108	104	102	103	01020000A034BF0D0003000000686694701B7827C0906DDB720E011DC09A9999999999E93F1084D38C95E327C040325D3A1A2A1CC09A9999999999E93F1084D38C95E328C040325D3A1A2A1AC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	1.63892272053361054	105	102	104	01020000A034BF0D0004000000686694701B7827C0906DDB720E011DC09A9999999999E93FE0FCB6D1F14427C0809A2035BB9A1CC09A9999999999E93FE0FCB6D1F14427C0203070B2579A17C09A9999999999E93F28A17C8670EB26C0B078FB1B55E716C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	0.429973598563549331	106	104	105	01020000A034BF0D000200000028A17C8670EB26C0B078FB1B55E716C09A9999999999E93F88AE9C064B0F26C0B078FB1B55E716C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	1.04999999600188687	107	105	106	01020000A034BF0D000300000088AE9C064B0F26C0B078FB1B55E716C09A9999999999E93F50773460860225C0B078FB1B55E716C09A9999999999E93FE06C256DB1F523C0B078FB1B55E716C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kw	0.944950908845351822	108	107	108	01020000A034BF0D0005000000E06C256DB1F523C0F0F826E7590B13C09A9999999999E93FE06C256DB1F523C03030B028BA7011C09A9999999999E93FE06C256DB1F523C0502EEA7BC41F11C09A9999999999E93FC06C256DB1F523C0102EEA7BC41F11C09A9999999999E93FC06C256DB1F523C0606A3F6271870EC09A9999999999E93F	\N	\N
first_floor	\N	0.0899999999996197175	109	109	107	01020000A034BF0D0002000000E06C256DB1F523C0A086E9DC826713C09A9999999999E93FE06C256DB1F523C0F0F826E7590B13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	0.874825463743505338	110	106	109	01020000A034BF0D0003000000E06C256DB1F523C0B078FB1B55E716C09A9999999999E93FE06C256DB1F523C0604F609B220215C09A9999999999E93FE06C256DB1F523C0A086E9DC826713C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kv	0.953872625850570866	111	110	111	01020000A034BF0D000500000088E0DC5CA2C321C0F0F826E7590B13C09A9999999999E93F88E0DC5CA2C321C03030B028BA7011C09A9999999999E93F88E0DC5CA2C321C060F6B3ACE54011C09A9999999999E93F6090243E1DD821C0B09624EAEF1711C09A9999999999E93F6090243E1DD821C02099CA851A970EC09A9999999999E93F	\N	\N
first_floor	\N	0.0899999999996197175	112	112	110	01020000A034BF0D000200000088E0DC5CA2C321C0A086E9DC826713C09A9999999999E93F88E0DC5CA2C321C0F0F826E7590B13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	1.72239760869136704	113	106	112	01020000A034BF0D0006000000E06C256DB1F523C0B078FB1B55E716C09A9999999999E93F6064167ADCE822C0B078FB1B55E716C09A9999999999E93FF8562C5F519E22C0B078FB1B55E716C09A9999999999E93F88E0DC5CA2C321C0D08B5C17F73115C09A9999999999E93F88E0DC5CA2C321C0604F609B220215C09A9999999999E93F88E0DC5CA2C321C0A086E9DC826713C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kd	0.945075263554304601	114	113	114	01020000A034BF0D000500000088AE9C064B0F26C0F0F826E7590B13C09A9999999999E93F88AE9C064B0F26C03030B028BA7011C09A9999999999E93F88AE9C064B0F26C020D03715E51F11C09A9999999999E93FA0AE9C064B0F26C0F0CF3715E51F11C09A9999999999E93FA0AE9C064B0F26C0A026A42F30870EC09A9999999999E93F	\N	\N
first_floor	\N	0.0899999999996197175	115	115	113	01020000A034BF0D000200000088AE9C064B0F26C0A086E9DC826713C09A9999999999E93F88AE9C064B0F26C0F0F826E7590B13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	0.874825463743505338	116	105	115	01020000A034BF0D000300000088AE9C064B0F26C0B078FB1B55E716C09A9999999999E93F88AE9C064B0F26C0604F609B220215C09A9999999999E93F88AE9C064B0F26C0A086E9DC826713C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kW	0.0226459209316883375	117	116	117	01020000A034BF0D0002000000307CAFA8562828C050F726E7590B13C09A9999999999E93F78DEA186893028C0C032422BF4FA12C09A9999999999E93F	\N	\N
first_floor	\N	0.116738465468237254	118	118	116	01020000A034BF0D0003000000280AB6A6490728C0A086E9DC826713C09A9999999999E93F280AB6A6490728C070DB19EB734D13C09A9999999999E93F307CAFA8562828C050F726E7590B13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	1.10446169916671755	119	104	118	01020000A034BF0D000400000028A17C8670EB26C0B078FB1B55E716C09A9999999999E93F30E804AD0F1C27C0A0EAEACE168616C09A9999999999E93F280AB6A6490728C0B0A688DBA2AF14C09A9999999999E93F280AB6A6490728C0A086E9DC826713C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	0.24801179887113603	120	119	120	01020000A034BF0D0003000000688875DFD06628C0A086E9DC826713C09A9999999999E93FA065A92255B228C0104151638BFE13C09A9999999999E93F688C0E9784C628C0104151638BFE13C09A9999999999E93F	\N	\N
first_floor	\N	0.127279220613563282	121	121	119	01020000A034BF0D0002000000C0409464BC3828C050F726E7590B13C09A9999999999E93F688875DFD06628C0A086E9DC826713C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kW	0.0226459209316883375	122	117	121	01020000A034BF0D000200000078DEA186893028C0C032422BF4FA12C09A9999999999E93FC0409464BC3828C050F726E7590B13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kW	1.04118803574269925	123	117	122	01020000A034BF0D000700000078DEA186893028C0C032422BF4FA12C09A9999999999E93F78DEA186893028C0902EB028BA7011C09A9999999999E93F78DEA186893028C000E1E53F5B4811C09A9999999999E93FD0FA5B62912228C0B0195AF76A2C11C09A9999999999E93FD0FA5B62912228C0E02249BDDC8C0EC09A9999999999E93F700AB2397E0228C06061A11A900C0EC09A9999999999E93F700AB2397E0228C0A0D1B7C8D7ED0DC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kj	1.60013307503500357	124	100	123	01020000A034BF0D0002000000906BECE3AC9126C0F8316F5BDB1420C09A9999999999E93FA85F773F685E23C0F8316F5BDB1420C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NP	1.96176447673742715	125	124	125	01020000A034BF0D0005000000082570794AC931C068550ABE186B28C09A9999999999E93F082570794AC931C0705AA5281E3A29C09A9999999999E93F0C42CADD85C831C06820F15FA73B29C09A9999999999E93F0C42CADD85C831C060B6EF8E3B8629C09A9999999999E93F5472A2F7BBC930C0D0553F5BCF832BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	126	126	124	01020000A034BF0D0002000000082570794AC931C0289D3316882B28C09A9999999999E93F082570794AC931C068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.1657874417945493	127	28	126	01020000A034BF0D0003000000082570794AC931C0786CC2FEA5D625C09A9999999999E93F082570794AC931C03876020EDC0E27C09A9999999999E93F082570794AC931C0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NP	3.49703926811741361	128	125	127	01020000A034BF0D00060000005472A2F7BBC930C0D0553F5BCF832BC09A9999999999E93F5472A2F7BBC930C0483EF09E1A1530C09A9999999999E93FA80C72DCCF9730C0F4A320BA064730C09A9999999999E93FA80C72DCCF9730C0441F5EAA7EFF30C09A9999999999E93F906AF0AF2EA330C02C7DDC7DDD0A31C09A9999999999E93F906AF0AF2EA330C03418283FC22731C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NP	1.35984340497680734	129	125	128	01020000A034BF0D00030000005472A2F7BBC930C0D0553F5BCF832BC09A9999999999E93F046FE3542D1A30C0284FC115B2242AC09A9999999999E93F5847053DAA6C2FC0284FC115B2242AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NK	2.0644775232227639	130	129	130	01020000A034BF0D0004000000C043F5649C0133C068550ABE186B28C09A9999999999E93FC043F5649C0133C0587C3BC6C48729C09A9999999999E93FC043F5649C0133C0A8C447C8EF8E29C09A9999999999E93F407F0EE7231034C0A83B7ACCFEAB2BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	131	131	129	01020000A034BF0D0002000000C043F5649C0133C0289D3316882B28C09A9999999999E93FC043F5649C0133C068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.1657874417945493	132	27	131	01020000A034BF0D0003000000C043F5649C0133C0786CC2FEA5D625C09A9999999999E93FC043F5649C0133C03876020EDC0E27C09A9999999999E93FC043F5649C0133C0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NK	3.38755183729869058	133	130	132	01020000A034BF0D0006000000407F0EE7231034C0A83B7ACCFEAB2BC09A9999999999E93F407F0EE7231034C034B18D57322930C09A9999999999E93F208CD6DFB02F34C014BE5550BF4830C09A9999999999E93F208CD6DFB02F34C070BE8E41EFFD30C09A9999999999E93FF80FE594552334C0983A808C4A0A31C09A9999999999E93FF80FE594552334C0541C6620062731C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NK	1.3273124510810661	134	130	133	01020000A034BF0D0003000000407F0EE7231034C0A83B7ACCFEAB2BC09A9999999999E93F7CF56A42CAD334C0284FC115B2242AC09A9999999999E93F3C0FFB33E41235C0284FC115B2242AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NJ	2.0677973646319483	135	134	135	01020000A034BF0D00050000004458A3AC7DFC38C068550ABE186B28C09A9999999999E93F4458A3AC7DFC38C0685AA5281E3A29C09A9999999999E93F4475FD10B9FB38C06820F15FA73B29C09A9999999999E93F4475FD10B9FB38C058B6EF8E3B8629C09A9999999999E93FD818A880BDE937C0286F9AAF32AA2BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	136	136	134	01020000A034BF0D00020000004458A3AC7DFC38C0289D3316882B28C09A9999999999E93F4458A3AC7DFC38C068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.16578744179462035	137	14	136	01020000A034BF0D00030000004458A3AC7DFC38C0506CC2FEA5D625C09A9999999999E93F4458A3AC7DFC38C03876020EDC0E27C09A9999999999E93F4458A3AC7DFC38C0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NJ	3.40741505543590417	138	135	137	01020000A034BF0D0006000000D818A880BDE937C0286F9AAF32AA2BC09A9999999999E93FD818A880BDE937C0F4CA1D494C2830C09A9999999999E93FB82570794AC937C014BE5550BF4830C09A9999999999E93FB82570794AC937C070BE8E41EFFD30C09A9999999999E93F2C4318C888D637C0E4DB36902D0B31C09A9999999999E93F2C4318C888D637C09C894580782A31C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NJ	1.32936878524932167	139	135	138	01020000A034BF0D0003000000D818A880BDE937C0286F9AAF32AA2BC09A9999999999E93FDC88BB33FD2637C0284FC115B2242AC09A9999999999E93F9CA24B2517E636C0284FC115B2242AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Ok	2.08872967956472255	140	139	140	01020000A034BF0D000500000068B4326F73253AC068550ABE186B28C09A9999999999E93F68B4326F73253AC0605AA5281E3A29C09A9999999999E93F98832AC3562B3AC0C0F894D0E44529C09A9999999999E93F98832AC3562B3AC0F8DD4B1EFE7B29C09A9999999999E93F24DF7C443B433BC01095F020C7AB2BC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.16578744179463456	142	13	141	01020000A034BF0D000300000068B4326F73253AC0486CC2FEA5D625C09A9999999999E93F68B4326F73253AC03876020EDC0E27C09A9999999999E93F68B4326F73253AC0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Ok	3.39432697435573516	143	140	142	01020000A034BF0D000600000024DF7C443B433BC01095F020C7AB2BC09A9999999999E93F24DF7C443B433BC0101B605B5CC72FC09A9999999999E93F24DF7C443B633BC04C48EB17350930C09A9999999999E93F24DF7C443B633BC0ACF8943DC1FD30C09A9999999999E93F04F6522C64563BC0CCE1BE55980A31C09A9999999999E93F04F6522C64563BC074355418BA2931C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Ok	1.35340433436699858	144	140	143	01020000A034BF0D000300000024DF7C443B433BC01095F020C7AB2BC09A9999999999E93F3003B61ED10A3CC0F84C7E6C9B1C2AC09A9999999999E93FC83B1535084B3CC0F84C7E6C9B1C2AC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.20000000000003437	145	2	144	01020000A034BF0D0003000000C4C1243DDC6F3EC0286CC2FEA5D625C09A9999999999E93FDCC1243DDC6F3EC0606CC2FEA5D625C09A9999999999E93FF4F457700FA33FC0286CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.527802277081462989	146	144	145	01020000A034BF0D0002000000F4F457700FA33FC0286CC2FEA5D625C09A9999999999E93F566393BE161540C0286CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.24000000000002331	147	145	146	01020000A034BF0D0002000000566393BE161540C0286CC2FEA5D625C09A9999999999E93F78E87E10CFB340C0186CC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	5.44443284002908001	148	146	147	01020000A034BF0D000200000078E87E10CFB340C0186CC2FEA5D625C09A9999999999E93F36815F3DB26C43C0F86BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.452562665769207229	149	147	148	01020000A034BF0D000200000036815F3DB26C43C0F86BC2FEA5D625C09A9999999999E93F7CF02BD09FA643C0F86BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.747437334230813155	150	148	149	01020000A034BF0D00030000007CF02BD09FA643C0F86BC2FEA5D625C09A9999999999E93FCE1AF9D64B0644C0F86BC2FEA5D625C09A9999999999E93FD21AF9D64B0644C0F06BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.66155232466857683	151	149	150	01020000A034BF0D0002000000D21AF9D64B0644C0F06BC2FEA5D625C09A9999999999E93F7EA01896F95A44C0E86BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.73844767533145728	152	150	151	01020000A034BF0D00030000007EA01896F95A44C0E86BC2FEA5D625C09A9999999999E93F064E2C0A7F3945C0E06BC2FEA5D625C09A9999999999E93F0A4E2C0A7F3945C0E06BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	3.4004251164103465	153	151	152	01020000A034BF0D00020000000A4E2C0A7F3945C0E06BC2FEA5D625C09A9999999999E93F680B822BC0EC46C0C86BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.641127208258211567	154	152	153	01020000A034BF0D0003000000680B822BC0EC46C0C86BC2FEA5D625C09A9999999999E93F680B822BC0EC46C0D06BC2FEA5D625C09A9999999999E93F221156A0D03E47C0C86BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.838872791741778201	155	153	154	01020000A034BF0D0002000000221156A0D03E47C0C86BC2FEA5D625C09A9999999999E93FA21559CF30AA47C0C06BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.561127208258241694	156	154	155	01020000A034BF0D0003000000A21559CF30AA47C0C06BC2FEA5D625C09A9999999999E93FA21559CF30AA47C0C86BC2FEA5D625C09A9999999999E93F564489D303F247C0C06BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	5.35844767533158972	157	155	156	01020000A034BF0D0003000000564489D303F247C0C06BC2FEA5D625C09A9999999999E93F82B49270E59F4AC0A06BC2FEA5D625C09A9999999999E93F82B49270E59F4AC0986BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.561552324668440406	158	156	157	01020000A034BF0D000200000082B49270E59F4AC0986BC2FEA5D625C09A9999999999E93F4E6DE562C6E74AC0986BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.638447675331562436	159	157	158	01020000A034BF0D00030000004E6DE562C6E74AC0986BC2FEA5D625C09A9999999999E93F1A4E2C0A7F394BC0986BC2FEA5D625C09A9999999999E93F1A4E2C0A7F394BC0906BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.741552324668447227	160	158	159	01020000A034BF0D00020000001A4E2C0A7F394BC0906BC2FEA5D625C09A9999999999E93FBEAAEF396A984BC0906BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.55844767533160677	161	159	160	01020000A034BF0D0003000000BEAAEF396A984BC0906BC2FEA5D625C09A9999999999E93F86B49270E55F4CC0906BC2FEA5D625C09A9999999999E93F86B49270E55F4CC0886BC2FEA5D625C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	3.27782804268160977	162	160	161	01020000A034BF0D000300000086B49270E55F4CC0886BC2FEA5D625C09A9999999999E93FC6C7FB3337EC4DC0786BC2FEA5D625C09A9999999999E93FBE963790A6FC4DC0982FD38DE89425C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	6.34239515832765299	163	161	162	01020000A034BF0D0006000000BE963790A6FC4DC0982FD38DE89425C09A9999999999E93FAE6A10B7E3FE4DC0982FD38DE89425C09A9999999999E93FAA6AC9444B0B4EC0882FB7C486C625C09A9999999999E93FDA9DFC777EBE4EC0882FB7C486C625C09A9999999999E93F0AD12FABB1314FC058FC8391539327C09A9999999999E93F71E8E793CF7950C058FC8391539327C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.01238658515596436	164	162	163	01020000A034BF0D000400000071E8E793CF7950C058FC8391539327C09A9999999999E93FF166068C0C7A50C058F077523B9527C09A9999999999E93F056A79DD9BB850C058F077523B9527C09A9999999999E93F09E94918F3B950C070E8FB28F59F27C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.607904212753084039	165	163	164	01020000A034BF0D000200000009E94918F3B950C070E8FB28F59F27C09A9999999999E93F0B215CFFDAE050C070E8FB28F59F27C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.99433908850542707	166	164	165	01020000A034BF0D00020000000B215CFFDAE050C070E8FB28F59F27C09A9999999999E93F05B2C63F7EA051C070E8FB28F59F27C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.966736519075482192	167	165	166	01020000A034BF0D000300000005B2C63F7EA051C070E8FB28F59F27C09A9999999999E93F05B2C63F7EA051C0681060D9862828C09A9999999999E93F05B2C63F7EA051C0D076C63FED8E29C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.13122376894452259	168	165	167	01020000A034BF0D000200000005B2C63F7EA051C070E8FB28F59F27C09A9999999999E93FCBB62738E4E851C070E8FB28F59F27C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.167620750528982398	169	167	168	01020000A034BF0D0002000000CBB62738E4E851C070E8FB28F59F27C09A9999999999E93F95208A849EF351C070E8FB28F59F27C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.44891976623282615	170	168	169	01020000A034BF0D000500000095208A849EF351C070E8FB28F59F27C09A9999999999E93F8B3AD6F0025052C018B85C8B18832AC09A9999999999E93F3FA1778B905952C018B85C8B18832AC09A9999999999E93F0D40A11DB16152C088AEA91C1DC42AC09A9999999999E93F0D40A11DB16152C0F8BDA57F49EC2AC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.39214721059835256	171	169	170	01020000A034BF0D00020000000D40A11DB16152C0F8BDA57F49EC2AC09A9999999999E93F0D40A11DB16152C098378F0411B52FC09A9999999999E93F	\N	\N
first_floor	\N	0.604338199065438175	172	171	172	01020000A034BF0D000200000015AF5FB3E79052C0F8BDA57F49EC2AC09A9999999999E93F7FDC7F2D95B752C0F8BDA57F49EC2AC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.737706600161004644	173	169	171	01020000A034BF0D00030000000D40A11DB16152C0F8BDA57F49EC2AC09A9999999999E93F378A5932526D52C0F8BDA57F49EC2AC09A9999999999E93F15AF5FB3E79052C0F8BDA57F49EC2AC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	4.03144711105501585	174	168	173	01020000A034BF0D000500000095208A849EF351C070E8FB28F59F27C09A9999999999E93FE98BC495C05C52C0D88D289FE45624C09A9999999999E93FE98BC495C05C52C0E0988167C6A621C09A9999999999E93F71CFCA12276252C0A07C4F7F927B21C09A9999999999E93F71CFCA12276252C0D8AB83DC21FE20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.655000031109011616	175	173	174	01020000A034BF0D000200000071CFCA12276252C0D8AB83DC21FE20C09A9999999999E93F71CFCA12276252C0B05F05658B5D1FC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	1.45346949794322988	176	175	176	01020000A034BF0D0004000000755CA765852252C0D8AB83DC21FE20C09A9999999999E93F9937A1E4EFFE51C0D8AB83DC21FE20C09A9999999999E93F61FEC49CB4EE51C0D8AB83DC21FE20C09A9999999999E93F41E5377191D151C0E8E21A80081520C09A9999999999E93F	\N	\N
first_floor	\N	0.244242939585035401	177	177	175	01020000A034BF0D000200000071CFCA12273252C0D8AB83DC21FE20C09A9999999999E93F755CA765852252C0D8AB83DC21FE20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.75	178	173	177	01020000A034BF0D000300000071CFCA12276252C0D8AB83DC21FE20C09A9999999999E93F4DF4D093BC5552C0D8AB83DC21FE20C09A9999999999E93F71CFCA12273252C0D8AB83DC21FE20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	1.56939305459496836	179	176	178	01020000A034BF0D000200000041E5377191D151C0E8E21A80081520C09A9999999999E93FBDE1A681206D51C0E8E21A80081520C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	0.812508065997468498	180	176	179	01020000A034BF0D000300000041E5377191D151C0E8E21A80081520C09A9999999999E93F6D1D9B4B54EF51C02043025AE34D1EC09A9999999999E93F6D1D9B4B54EF51C0D088E7334CAF1DC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	0.452317861665538001	181	179	180	01020000A034BF0D00020000006D1D9B4B54EF51C0D088E7334CAF1DC09A9999999999E93F1D1F5481CC0352C0E06D57D8C8671CC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	1.82371771601757882	182	179	181	01020000A034BF0D00040000006D1D9B4B54EF51C0D088E7334CAF1DC09A9999999999E93F9548DAE5F0E851C0503BDAD715491DC09A9999999999E93F9548DAE5F0E851C0E0B95E18678B17C09A9999999999E93FA18F30A7BFDD51C0B02AC32D53D816C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	0.454891787035023754	183	181	182	01020000A034BF0D0002000000A18F30A7BFDD51C0B02AC32D53D816C09A9999999999E93F6D6DBFB4A2C051C0B02AC32D53D816C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	1.04999999600187266	184	182	183	01020000A034BF0D00030000006D6DBFB4A2C051C0B02AC32D53D816C09A9999999999E93F2DF9271B099F51C0B02AC32D53D816C09A9999999999E93F398590816F7D51C0B02AC32D53D816C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fO	0.920346444524519858	185	184	185	01020000A034BF0D0005000000398590816F7D51C0D06BAE083BFC12C09A9999999999E93F398590816F7D51C010A3374A9B6111C09A9999999999E93F398590816F7D51C0507418EAB51011C09A9999999999E93F118590816F7D51C0D07118EAB51011C09A9999999999E93F118590816F7D51C0A0119B78979B0EC09A9999999999E93F	\N	\N
first_floor	\N	0.0899999999993923439	186	186	184	01020000A034BF0D0002000000398590816F7D51C080F870FE635813C09A9999999999E93F398590816F7D51C0D06BAE083BFC12C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	0.874935855285499997	187	183	186	01020000A034BF0D0003000000398590816F7D51C0B02AC32D53D816C09A9999999999E93F398590816F7D51C040C1E7BC03F314C09A9999999999E93F398590816F7D51C080F870FE635813C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fV	0.942059195305055441	188	187	188	01020000A034BF0D0005000000D33D983A013851C0D06BAE083BFC12C09A9999999999E93FD33D983A013851C010A3374A9B6111C09A9999999999E93FD33D983A013851C0F033A132F03E11C09A9999999999E93F5F33C196903A51C030DB1170FA1511C09A9999999999E93F5F33C196903A51C0E03EA86C0E910EC09A9999999999E93F	\N	\N
first_floor	\N	0.0899999999993923439	189	189	187	01020000A034BF0D0002000000D33D983A013851C080F870FE635813C09A9999999999E93FD33D983A013851C0D06BAE083BFC12C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	1.70199870912001217	190	183	189	01020000A034BF0D0006000000398590816F7D51C0B02AC32D53D816C09A9999999999E93FF110F9E7D55B51C0B02AC32D53D816C09A9999999999E93FAD8D2C802B5451C0B02AC32D53D816C09A9999999999E93FD33D983A013851C0202D7ED4AE1515C09A9999999999E93FD33D983A013851C040C1E7BC03F314C09A9999999999E93FD33D983A013851C080F870FE635813C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f5	0.920346444524489327	191	190	191	01020000A034BF0D00050000006D6DBFB4A2C051C0D06BAE083BFC12C09A9999999999E93F6D6DBFB4A2C051C010A3374A9B6111C09A9999999999E93F6D6DBFB4A2C051C0D07318EAB51011C09A9999999999E93F4F6DBFB4A2C051C0F07118EAB51011C09A9999999999E93F4F6DBFB4A2C051C060119B78979B0EC09A9999999999E93F	\N	\N
first_floor	\N	0.0899999999993923439	192	192	190	01020000A034BF0D00020000006D6DBFB4A2C051C080F870FE635813C09A9999999999E93F6D6DBFB4A2C051C0D06BAE083BFC12C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	0.874935855285499997	193	182	192	01020000A034BF0D00030000006D6DBFB4A2C051C0B02AC32D53D816C09A9999999999E93F6D6DBFB4A2C051C040C1E7BC03F314C09A9999999999E93F6D6DBFB4A2C051C080F870FE635813C09A9999999999E93F	\N	\N
first_floor	\N	0.0225805231300776586	194	193	194	01020000A034BF0D0002000000D34E483C5E0552C080F870FE635813C09A9999999999E93F1D5111D6630652C0E0D3E0610A4813C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	1.13135645983353728	195	181	193	01020000A034BF0D0005000000A18F30A7BFDD51C0B02AC32D53D816C09A9999999999E93F6DE1564E3CE251C0000E5EBB889016C09A9999999999E93FABCB273A3C0152C0206A4FFE89A014C09A9999999999E93FABCB273A3C0152C0002B7920849A13C09A9999999999E93FD34E483C5E0552C080F870FE635813C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f6	0.936812411220175556	196	195	196	01020000A034BF0D00050000001D5111D6630652C02069AE083BFC12C09A9999999999E93F1D5111D6630652C060A0374A9B6111C09A9999999999E93F1D5111D6630652C06070078DC23911C09A9999999999E93F475BE879D40352C0001378CACC1011C09A9999999999E93F475BE879D40352C060AB1840CD9B0EC09A9999999999E93F	\N	\N
first_floor	\N	0.074033158971985813	197	194	195	01020000A034BF0D00020000001D5111D6630652C0E0D3E0610A4813C09A9999999999E93F1D5111D6630652C02069AE083BFC12C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f3	0.311172288924506435	198	197	198	01020000A034BF0D00030000006753DA6F690752C080F870FE635813C09A9999999999E93F8988E9A0BB1352C0904A640F871D14C09A9999999999E93F898BBC2C391652C0904A640F871D14C09A9999999999E93F	\N	\N
first_floor	\N	0.0225805231300776586	199	194	197	01020000A034BF0D00020000001D5111D6630652C0E0D3E0610A4813C09A9999999999E93F6753DA6F690752C080F870FE635813C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048hL	5.52122048754753525	200	199	200	01020000A034BF0D000600000005215CFFDAE050C0308D033138A42CC09A9999999999E93F01215CFFDAE050C090F13E1088712DC09A9999999999E93F01215CFFDAE050C0F0269DCAD1FD2DC09A9999999999E93F9B9DC8D5A9C550C0204239175BD72EC09A9999999999E93F9B9DC8D5A9C550C08430F191E31033C09A9999999999E93F9B9DC8D5A9C550C0B8C98A2B7DAA33C09A9999999999E93F	\N	\N
first_floor	\N	0.200000000000002842	201	201	199	01020000A034BF0D000200000007215CFFDAE050C0C8269DCAD13D2CC09A9999999999E93F05215CFFDAE050C0308D033138A42CC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.30832390874199689	202	164	201	01020000A034BF0D00030000000B215CFFDAE050C070E8FB28F59F27C09A9999999999E93F0B215CFFDAE050C068C261EB81702BC09A9999999999E93F07215CFFDAE050C0C8269DCAD13D2CC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048hL	1.45462351424960001	203	200	202	01020000A034BF0D00040000009B9DC8D5A9C550C0B8C98A2B7DAA33C09A9999999999E93F9B9DC8D5A9C550C0F0BA417B73B833C09A9999999999E93FA9AE5739A5C550C0B47605ED85B833C09A9999999999E93FC95671C5106C50C0B47605ED85B833C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fC	1.03229707249472558	204	203	204	01020000A034BF0D000500000039548F320E1C51C0B8C98A2B7DAA33C09A9999999999E93FDFB4E2DFEE3551C0B8C98A2B7DAA33C09A9999999999E93F659E0911F73551C0D06F26F09DAA33C09A9999999999E93F918F6E829B3F51C0D06F26F09DAA33C09A9999999999E93F8B99DDEA2C5551C0B897E291E30034C09A9999999999E93F	\N	\N
first_floor	\N	0.25	205	205	203	01020000A034BF0D000200000039548F320E0C51C0B8C98A2B7DAA33C09A9999999999E93F39548F320E1C51C0B8C98A2B7DAA33C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048hL	1.09987563520050458	206	200	205	01020000A034BF0D00030000009B9DC8D5A9C550C0B8C98A2B7DAA33C09A9999999999E93F5B2F89B178E850C0B8C98A2B7DAA33C09A9999999999E93F39548F320E0C51C0B8C98A2B7DAA33C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fC	3.27866322730670579	207	204	206	01020000A034BF0D00060000008B99DDEA2C5551C0B897E291E30034C09A9999999999E93FE7B196E055D951C0B897E291E30034C09A9999999999E93F51D4E22AB9EB51C0140EB26856B733C09A9999999999E93FAD7CEAD536F051C0140EB26856B733C09A9999999999E93F29C01B1F371052C02400ED43553733C09A9999999999E93FB9893B5B231252C02400ED43553733C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fC	0.908632209018369275	208	204	207	01020000A034BF0D00020000008B99DDEA2C5551C0B897E291E30034C09A9999999999E93F39548F320E2C51C000AD1B735EA534C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	6.51757263345607463	209	163	208	01020000A034BF0D000300000009E94918F3B950C070E8FB28F59F27C09A9999999999E93FB76D2518584C50C0F8C21F2ACD0C2BC09A9999999999E93FB76D2518584C50C00C73BC8BE09E31C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f9	2.49237082320001235	210	209	210	01020000A034BF0D000400000027715965B01550C00C73BC8BE09E31C09A9999999999E93F464497C835E44FC00C73BC8BE09E31C09A9999999999E93FCA1217520DE14FC0807C665C8F9831C09A9999999999E93FFACCDAAFEF344FC0CCE03282BCF032C09A9999999999E93F	\N	\N
first_floor	\N	0.258247074031118018	211	211	209	01020000A034BF0D00020000003DC11584372650C00C73BC8BE09E31C09A9999999999E93F27715965B01550C00C73BC8BE09E31C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.59573842554701173	212	208	211	01020000A034BF0D0003000000B76D2518584C50C00C73BC8BE09E31C09A9999999999E93F1BE61B05CD4950C00C73BC8BE09E31C09A9999999999E93F3DC11584372650C00C73BC8BE09E31C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f9	0.0299574680590118415	213	210	212	01020000A034BF0D0002000000FACCDAAFEF344FC0CCE03282BCF032C09A9999999999E93F7266B89BEF344FC0B00C1CCD67F832C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f9	1.17744322134485313	214	210	213	01020000A034BF0D0005000000FACCDAAFEF344FC0CCE03282BCF032C09A9999999999E93FA6FC14340A124FC02440A78AF1AA32C09A9999999999E93F6E47867673084FC02440A78AF1AA32C09A9999999999E93F5A408E7673C84EC0F831B78AF12A32C09A9999999999E93F2ACE8A1230C74EC0F831B78AF12A32C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f9	1.40211739276940683	215	213	214	01020000A034BF0D00030000002ACE8A1230C74EC0F831B78AF12A32C09A9999999999E93FE2E73E0B30574EC06C651F7CF14A31C09A9999999999E93FEA7130D51B424EC06C651F7CF14A31C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048f9	1.29139648914577454	216	213	215	01020000A034BF0D00030000002ACE8A1230C74EC0F831B78AF12A32C09A9999999999E93F6A2EAB61AB534EC0747176ECFA1133C09A9999999999E93F02377E00BD514EC0747176ECFA1133C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.262490821504570704	217	208	216	01020000A034BF0D0002000000B76D2518584C50C00C73BC8BE09E31C09A9999999999E93FB76D2518584C50C0CC4FF22413E231C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	3.49451475553934765	218	162	217	01020000A034BF0D000300000071E8E793CF7950C058FC8391539327C09A9999999999E93F85DC36B23D9950C0B05B0C9FE29726C09A9999999999E93F85DC36B23D9950C018C2720549FE20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.16578744179477667	290	148	289	01020000A034BF0D00030000007CF02BD09FA643C0F86BC2FEA5D625C09A9999999999E93F7CF02BD09FA643C04076020EDC0E27C09A9999999999E93F7CF02BD09FA643C0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	2.63335439555776096	219	161	218	01020000A034BF0D0005000000BE963790A6FC4DC0982FD38DE89425C09A9999999999E93FEA59A73673AA4DC0503C92271B4C24C09A9999999999E93FEA59A73673AA4DC0D04753E376B021C09A9999999999E93FB626740340974DC0007B8616AA6321C09A9999999999E93FB626740340974DC02084700FA3F820C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	1.46276510858943798	220	219	220	01020000A034BF0D0004000000A2A11379631F4EC02084700FA3F820C09A9999999999E93F5AEB1F7B8E664EC02084700FA3F820C09A9999999999E93F724584B66D864EC02084700FA3F820C09A9999999999E93F0A196671F6C14EC0C035E923800A20C09A9999999999E93F	\N	\N
first_floor	\N	0.261588322189993505	221	221	219	01020000A034BF0D00020000007A382FBFE7FD4DC02084700FA3F820C09A9999999999E93FA2A11379631F4EC02084700FA3F820C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.801993814794997206	222	218	221	01020000A034BF0D0003000000B626740340974DC02084700FA3F820C09A9999999999E93FC2EE22BDBCB64DC02084700FA3F820C09A9999999999E93F7A382FBFE7FD4DC02084700FA3F820C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	1.55894712300903393	223	220	222	01020000A034BF0D00020000000A196671F6C14EC0C035E923800A20C09A9999999999E93F3ADBB40582894FC0C035E923800A20C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	0.80622524884276614	224	220	223	01020000A034BF0D00030000000A196671F6C14EC0C035E923800A20C09A9999999999E93F7E87972A08874EC010DF5D118E3D1EC09A9999999999E93F7E87972A08874EC090AF1EB1B49E1DC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	1.8189075880607759	225	223	224	01020000A034BF0D00060000007E87972A08874EC090AF1EB1B49E1DC09A9999999999E93F46341E279A904EC05049E9CC24521DC09A9999999999E93F46341E279A904EC05049E9CC24521CC09A9999999999E93FC6B3B7C033924EC0504D1D0058451CC09A9999999999E93FC6B3B7C033924EC0D0EDF74D105A17C09A9999999999E93F3637CF3EBAA54EC050D23B5DDCBD16C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	0.500186748687241334	226	224	225	01020000A034BF0D00020000003637CF3EBAA54EC050D23B5DDCBD16C09A9999999999E93FC2F75E5DC0E54EC050D23B5DDCBD16C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	1.0499999960019295	227	225	226	01020000A034BF0D0003000000C2F75E5DC0E54EC050D23B5DDCBD16C09A9999999999E93F22E08D90F3284FC050D23B5DDCBD16C09A9999999999E93F32C8BCC3266C4FC050D23B5DDCBD16C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fH	0.961856137703103187	228	227	228	01020000A034BF0D0005000000A281797AB7F54FC040599F9BB6E112C09A9999999999E93FB681797AB7F54FC0809028DD164711C09A9999999999E93FB2FD58403CF74FC0C0B02CAEF03A11C09A9999999999E93F1A9627C298F04FC00074A1BCD40511C09A9999999999E93F1A9627C298F04FC0808FD5649B470EC09A9999999999E93F	\N	\N
first_floor	\N	0.090000000000358682	229	229	227	01020000A034BF0D00020000009E81797AB7F54FC030EA6191DF3D13C09A9999999999E93FA281797AB7F54FC040599F9BB6E112C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	1.68596100092192858	230	226	229	01020000A034BF0D000600000032C8BCC3266C4FC050D23B5DDCBD16C09A9999999999E93F9AB0EBF659AF4FC050D23B5DDCBD16C09A9999999999E93F9E158C6415BC4FC050D23B5DDCBD16C09A9999999999E93F8E81797AB7F54FC0C072D0ADCBF014C09A9999999999E93F8E81797AB7F54FC0F0B2D84F7FD814C09A9999999999E93F9E81797AB7F54FC030EA6191DF3D13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fK	0.952910487115769422	231	230	231	01020000A034BF0D000500000046C8BCC3266C4FC040599F9BB6E112C09A9999999999E93F56C8BCC3266C4FC0809028DD164711C09A9999999999E93F72BBBE1935714FC0C0F7182DA41E11C09A9999999999E93F5EC8BCC3266C4FC0205F097D31F610C09A9999999999E93F5EC8BCC3266C4FC040B905E4E1660EC09A9999999999E93F	\N	\N
first_floor	\N	0.090000000000358682	232	232	230	01020000A034BF0D000200000042C8BCC3266C4FC030EA6191DF3D13C09A9999999999E93F46C8BCC3266C4FC040599F9BB6E112C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	0.874987778830501384	233	226	232	01020000A034BF0D000300000032C8BCC3266C4FC050D23B5DDCBD16C09A9999999999E93F32C8BCC3266C4FC0F0B2D84F7FD814C09A9999999999E93F42C8BCC3266C4FC030EA6191DF3D13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kh	0.952910487115782523	234	233	234	01020000A034BF0D0005000000D6F75E5DC0E54EC040599F9BB6E112C09A9999999999E93FEAF75E5DC0E54EC0809028DD164711C09A9999999999E93FFAEA60B3CEEA4EC010F8182DA41E11C09A9999999999E93FE6F75E5DC0E54EC0605F097D31F610C09A9999999999E93FE6F75E5DC0E54EC0C0B805E4E1660EC09A9999999999E93F	\N	\N
first_floor	\N	0.090000000000358682	235	235	233	01020000A034BF0D0002000000D2F75E5DC0E54EC030EA6191DF3D13C09A9999999999E93FD6F75E5DC0E54EC040599F9BB6E112C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	0.874987778830501384	236	225	235	01020000A034BF0D0003000000C2F75E5DC0E54EC050D23B5DDCBD16C09A9999999999E93FC2F75E5DC0E54EC0F0B2D84F7FD814C09A9999999999E93FD2F75E5DC0E54EC030EA6191DF3D13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048kk	0.952486239310288418	237	236	237	01020000A034BF0D0007000000FAF10F4A34644EC040599F9BB6E112C09A9999999999E93FFEF10F4A34644EC070CC836B12CA11C09A9999999999E93FB60F302A8D624EC010BA846CD9BC11C09A9999999999E93FBA0F302A8D624EC0709028DD164711C09A9999999999E93FAA8E9AE601664EC00099D4F9702B11C09A9999999999E93F26C4F309175E4EC0E0449E141AEC10C09A9999999999E93F26C4F309175E4EC0C0EDDBB4107B0EC09A9999999999E93F	\N	\N
first_floor	\N	0.090000000000358682	238	238	236	01020000A034BF0D0002000000FAF10F4A34644EC030EA6191DF3D13C09A9999999999E93FFAF10F4A34644EC040599F9BB6E112C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	1.0870239143252507	239	224	238	01020000A034BF0D00060000003637CF3EBAA54EC050D23B5DDCBD16C09A9999999999E93FA20F302A8DA24EC0B09542B873A416C09A9999999999E93F6E71A9E3CD654EC020A40D8479BE14C09A9999999999E93F7671A9E3CD654EC040FF09E051C713C09A9999999999E93FF6F10F4A34644EC030033E1385BA13C09A9999999999E93FFAF10F4A34644EC030EA6191DF3D13C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048fI	0.438053546813286288	240	223	239	01020000A034BF0D00020000007E87972A08874EC090AF1EB1B49E1DC09A9999999999E93F662FF341625F4EC0D0EEFB6B85611CC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	0.586974378475034086	241	218	240	01020000A034BF0D0002000000B626740340974DC02084700FA3F820C09A9999999999E93FB626740340974DC0B078244F36981FC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Na	4.02253255828899547	242	241	242	01020000A034BF0D000B000000DAB1C2ECD7114CC0680F4036204A23C09A9999999999E93FDAB1C2ECD7114CC0600AA5CB1A7B22C09A9999999999E93F622A0305F4124CC04828A36AAA7622C09A9999999999E93F622A0305F4124CC090CA108FE43122C09A9999999999E93F1A9F961DF8484CC0A8F7C22CD45921C09A9999999999E93F1A9F961DF8484CC0D891020EFB5920C09A9999999999E93F8E0D45AAD4644CC010B091B611D51FC09A9999999999E93F8E0D45AAD4644CC00015E8FE66611AC09A9999999999E93F8E0D45AAD4644CC090F23E6D3A8718C09A9999999999E93FF2BA11D6325C4CC0B05DA4CB2B4218C09A9999999999E93FF2BA11D6325C4CC0B0790C41C7AC17C09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318057816	243	243	241	01020000A034BF0D0002000000DAB1C2ECD7114CC0F03951E7C38123C09A9999999999E93FDAB1C2ECD7114CC0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035123385	244	160	243	01020000A034BF0D000300000086B49270E55F4CC0886BC2FEA5D625C09A9999999999E93FDAB1C2ECD7114CC0E06082EF6F9E24C09A9999999999E93FDAB1C2ECD7114CC0F03951E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Ot	1.88010631947096618	245	244	245	01020000A034BF0D0004000000BEAAEF396A984BC068550ABE186B28C09A9999999999E93FBEAAEF396A984BC0587C3BC6C48729C09A9999999999E93FBEAAEF396A984BC018540ABE18EB29C09A9999999999E93F2E4C9853B3FE4BC0D8D9AC243D842BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	246	246	244	01020000A034BF0D0002000000BEAAEF396A984BC0289D3316882B28C09A9999999999E93FBEAAEF396A984BC068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.16578744179496141	247	159	246	01020000A034BF0D0003000000BEAAEF396A984BC0906BC2FEA5D625C09A9999999999E93FBEAAEF396A984BC03876020EDC0E27C09A9999999999E93FBEAAEF396A984BC0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Ot	3.49931646816763697	248	245	247	01020000A034BF0D00060000002E4C9853B3FE4BC0D8D9AC243D842BC09A9999999999E93F2E4C9853B3FE4BC0888E8D2D1C1830C09A9999999999E93FC2C2D46CCA154CC0B07B06604A4630C09A9999999999E93FC2C2D46CCA154CC0A4F9EEBEFC0331C09A9999999999E93F121A1B61E1114CC0044B62D6CE0B31C09A9999999999E93F121A1B61E1114CC024F45A91932B31C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Ot	1.26935150122306029	249	245	248	01020000A034BF0D00030000002E4C9853B3FE4BC0D8D9AC243D842BC09A9999999999E93F4A8BD96CE3554CC068DDA7BF7C272AC09A9999999999E93F8A372226107D4CC068DDA7BF7C272AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NZ	3.96327309345203904	250	249	250	01020000A034BF0D0005000000724B5C8671EB4AC0D80E4036204A23C09A9999999999E93F724B5C8671EB4AC0E8E70E2E742D22C09A9999999999E93F724B5C8671EB4AC01846006D942B22C09A9999999999E93FD6723B71F3314BC088A883C18C1121C09A9999999999E93FD6723B71F3314BC03039B25380A317C09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318370455	251	251	249	01020000A034BF0D0002000000724B5C8671EB4AC0103A51E7C38123C09A9999999999E93F724B5C8671EB4AC0D80E4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035117967	252	158	251	01020000A034BF0D00030000001A4E2C0A7F394BC0906BC2FEA5D625C09A9999999999E93F724B5C8671EB4AC0F86082EF6F9E24C09A9999999999E93F724B5C8671EB4AC0103A51E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Ox	2.07979133821970974	253	252	253	01020000A034BF0D00050000004E6DE562C6E74AC068550ABE186B28C09A9999999999E93F4E6DE562C6E74AC0585AA5281E3A29C09A9999999999E93FEE00FE661CE64AC0D80B4318C64029C09A9999999999E93FEE00FE661CE64AC0D8CA9DD61C8129C09A9999999999E93F7AE91EFC805B4AC0A8281A828AAB2BC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.1657874417949472	255	157	254	01020000A034BF0D00030000004E6DE562C6E74AC0986BC2FEA5D625C09A9999999999E93F4E6DE562C6E74AC03876020EDC0E27C09A9999999999E93F4E6DE562C6E74AC0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Ox	3.40476930291122271	256	253	255	01020000A034BF0D00060000007AE91EFC805B4AC0A8281A828AAB2BC09A9999999999E93F7AE91EFC805B4AC0E4229913972B30C09A9999999999E93F4ADE226D9D4B4AC0443991315E4B30C09A9999999999E93F4ADE226D9D4B4AC08CB556F793FE30C09A9999999999E93F0AC43961E1514AC00C8184DF1B0B31C09A9999999999E93F0AC43961E1514AC0A49DDFC7092B31C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Ox	1.32059365593731703	257	253	256	01020000A034BF0D00030000007AE91EFC805B4AC0A8281A828AAB2BC09A9999999999E93FEA91579972FA49C060CAFCF650272AC09A9999999999E93F8A7B5F7BABDA49C060CAFCF650272AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6N_	4.00734795006558109	258	257	258	01020000A034BF0D000A000000DAB1C2ECD7514AC0680F4036204A23C09A9999999999E93FDAB1C2ECD7514AC0680AA5CB1A7B22C09A9999999999E93F52FAFA58D7504AC0402C867C187722C09A9999999999E93F52FAFA58D7504AC0A0C62D7D763122C09A9999999999E93FDE2C15063A114AC0D8909631013321C09A9999999999E93FDE2C15063A114AC0B8264992D03220C09A9999999999E93FDE2C15063A014AC0704D9224A1E51FC09A9999999999E93FDE2C15063A014AC0501ADAB65A7518C09A9999999999E93FE2709892A7074AC030FABF52EE4118C09A9999999999E93FE2709892A7074AC07048720F2BAD17C09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318128871	259	259	257	01020000A034BF0D0002000000DAB1C2ECD7514AC0183A51E7C38123C09A9999999999E93FDAB1C2ECD7514AC0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035117967	260	156	259	01020000A034BF0D000300000082B49270E59F4AC0986BC2FEA5D625C09A9999999999E93FDAB1C2ECD7514AC0006182EF6F9E24C09A9999999999E93FDAB1C2ECD7514AC0183A51E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Oy	2.02763073589263421	261	260	261	01020000A034BF0D0004000000564489D303F247C068550ABE186B28C09A9999999999E93F564489D303F247C0587C3BC6C48729C09A9999999999E93F564489D303F247C0D820D78AE5B729C09A9999999999E93FAE1C522FB46E48C03882FAF9A6AA2BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	262	262	260	01020000A034BF0D0002000000564489D303F247C0289D3316882B28C09A9999999999E93F564489D303F247C068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.16578744179487614	263	155	262	01020000A034BF0D0003000000564489D303F247C0C06BC2FEA5D625C09A9999999999E93F564489D303F247C03876020EDC0E27C09A9999999999E93F564489D303F247C0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Oy	3.41019758974730847	264	261	263	01020000A034BF0D0006000000AE1C522FB46E48C03882FAF9A6AA2BC09A9999999999E93FAE1C522FB46E48C0AC4F894F252B30C09A9999999999E93F7A1156A0D07E48C0443991315E4B30C09A9999999999E93F7A1156A0D07E48C08CB556F793FE30C09A9999999999E93F6E2AA0C7477848C0A483C2A8A50B31C09A9999999999E93F6E2AA0C7477848C03CA01D91932B31C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Oy	1.32161053981249799	265	261	264	01020000A034BF0D0003000000AE1C522FB46E48C03882FAF9A6AA2BC09A9999999999E93FA28A11B089CF48C060CAFCF650272AC09A9999999999E93F3A741992C2EF48C060CAFCF650272AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Nz	3.57187488082289617	266	265	266	01020000A034BF0D00090000003E1829533EF847C0680F4036204A23C09A9999999999E93F3E1829533EF847C078E80E2E742D22C09A9999999999E93F3E1829533EF847C058F4F36A69E421C09A9999999999E93FF2083A0CBB6E48C08831B086760A20C09A9999999999E93FF2083A0CBB6E48C0D08EC5CE8B141EC09A9999999999E93FF2083A0CBB7E48C0D08EC5CE8B941DC09A9999999999E93FF2083A0CBB7E48C0F0D8A60C70C61AC09A9999999999E93F2A80F0CB5B7848C0B0925A0A76931AC09A9999999999E93F2A80F0CB5B7848C0B070F6186B1D1AC09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318242558	267	267	265	01020000A034BF0D00020000003E1829533EF847C0583A51E7C38123C09A9999999999E93F3E1829533EF847C0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035108907	268	154	267	01020000A034BF0D0003000000A21559CF30AA47C0C06BC2FEA5D625C09A9999999999E93F3E1829533EF847C0406182EF6F9E24C09A9999999999E93F3E1829533EF847C0583A51E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6OX	2.03012271375862774	269	268	269	01020000A034BF0D0004000000221156A0D03E47C068550ABE186B28C09A9999999999E93F221156A0D03E47C0587C3BC6C48729C09A9999999999E93F221156A0D03E47C08823D78AE5B729C09A9999999999E93F12360887E6C146C0C88F0EF08DAB2BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	270	270	268	01020000A034BF0D0002000000221156A0D03E47C0289D3316882B28C09A9999999999E93F221156A0D03E47C068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.16578744179486193	271	153	270	01020000A034BF0D0003000000221156A0D03E47C0C86BC2FEA5D625C09A9999999999E93F221156A0D03E47C03876020EDC0E27C09A9999999999E93F221156A0D03E47C0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6OX	3.40547304062686207	272	269	271	01020000A034BF0D000600000012360887E6C146C0C88F0EF08DAB2BC09A9999999999E93F12360887E6C146C014F38D0B732B30C09A9999999999E93F12360887E6B146C014F38D0B734B30C09A9999999999E93F12360887E6B146C0AC0EE53030FE30C09A9999999999E93F7A9ABDC747B846C07CD74FB2F20A31C09A9999999999E93F7A9ABDC747B846C0C47D1AC8092B31C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6OX	1.32098559466730214	273	269	272	01020000A034BF0D000300000012360887E6C146C0C88F0EF08DAB2BC09A9999999999E93FDE6B02D9CD6046C00067F7372B272AC09A9999999999E93F12890472084146C00067F7372B272AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Nu	3.57627822230684078	274	273	274	01020000A034BF0D0009000000020E52AFCD3A47C0680F4036204A23C09A9999999999E93F020E52AFCD3A47C078E80E2E742D22C09A9999999999E93F020E52AFCD3A47C0C83463A547ED21C09A9999999999E93F5A22F063EDC146C02886DB77C60920C09A9999999999E93F5A22F063EDC146C050115EFB86121EC09A9999999999E93F62630EBF55B246C0901950D4C9951DC09A9999999999E93F62630EBF55B246C01005A09BE8C31AC09A9999999999E93F36F00DCC5BB846C0909EA333B8931AC09A9999999999E93F36F00DCC5BB846C0D09EFDF7511E1AC09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318270979	275	275	273	01020000A034BF0D0002000000020E52AFCD3A47C0683A51E7C38123C09A9999999999E93F020E52AFCD3A47C0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035107309	276	152	275	01020000A034BF0D0003000000680B822BC0EC46C0C86BC2FEA5D625C09A9999999999E93F020E52AFCD3A47C0586182EF6F9E24C09A9999999999E93F020E52AFCD3A47C0683A51E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Nt	4.67670373019338914	277	276	277	01020000A034BF0D000B000000724B5C8671EB44C0680F4036204A23C09A9999999999E93F724B5C8671EB44C078E80E2E742D22C09A9999999999E93F724B5C8671EB44C07079DFBC210322C09A9999999999E93F982CC7075E1F45C0D8F433B76F3321C09A9999999999E93F982CC7075E1F45C0587707BDEC3220C09A9999999999E93FA26DE562C62F45C060E61CA196E21FC09A9999999999E93FA26DE562C62F45C05038D3CE1B7718C09A9999999999E93FA82D18A3FF2845C0803869D0E54018C09A9999999999E93FA82D18A3FF2845C0D038C3947FCB17C09A9999999999E93F8E522D8DDA6A45C0A0111A44A8BC15C09A9999999999E93F8E522D8DDA6A45C0B0E176D36AB215C09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318370455	278	278	276	01020000A034BF0D0002000000724B5C8671EB44C0A03A51E7C38123C09A9999999999E93F724B5C8671EB44C0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.4183696703510229	279	151	278	01020000A034BF0D00030000000A4E2C0A7F3945C0E06BC2FEA5D625C09A9999999999E93F724B5C8671EB44C0906182EF6F9E24C09A9999999999E93F724B5C8671EB44C0A03A51E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6OY	2.01930946162143421	280	279	280	01020000A034BF0D00040000007EA01896F95A44C068550ABE186B28C09A9999999999E93F7EA01896F95A44C0587C3BC6C48729C09A9999999999E93F7EA01896F95A44C0E0F77AFB22C229C09A9999999999E93F46693BBA19D544C0001B068CA3AA2BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	281	281	279	01020000A034BF0D00020000007EA01896F95A44C0289D3316882B28C09A9999999999E93F7EA01896F95A44C068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.16578744179480509	282	150	281	01020000A034BF0D00030000007EA01896F95A44C0E86BC2FEA5D625C09A9999999999E93F7EA01896F95A44C03876020EDC0E27C09A9999999999E93F7EA01896F95A44C0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6OY	3.40949385203173794	283	280	282	01020000A034BF0D000600000046693BBA19D544C0001B068CA3AA2BC09A9999999999E93F46693BBA19D544C0B0B889D9FD2A30C09A9999999999E93F46693BBA19E544C0B0B889D9FD4A30C09A9999999999E93F46693BBA19E544C01049E962A5FE30C09A9999999999E93FE200242EAEDE44C0D819187B7C0B31C09A9999999999E93FE200242EAEDE44C020C0E290932B31C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6OY	1.32203313285104018	284	280	283	01020000A034BF0D000300000046693BBA19D544C0001B068CA3AA2BC09A9999999999E93F46163FCFF73545C00067F7372B272AC09A9999999999E93F7A334168325645C00067F7372B272AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6No	4.66865458146079426	285	284	285	01020000A034BF0D00070000003E1829533EB843C0680F4036204A23C09A9999999999E93F3E1829533EB843C078E80E2E742D22C09A9999999999E93F3E1829533EB843C030C3CA70172C22C09A9999999999E93F2C8F819ED0FE43C078E76843CE1121C09A9999999999E93F2C8F819ED0FE43C000E3225AD4C617C09A9999999999E93FD07375614F4144C0E0BD8342DEB215C09A9999999999E93FD07375614F4144C0F025328ABFAD15C09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318427299	286	286	284	01020000A034BF0D00020000003E1829533EB843C0C03A51E7C38123C09A9999999999E93F3E1829533EB843C0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035098693	287	149	286	01020000A034BF0D0003000000D21AF9D64B0644C0F06BC2FEA5D625C09A9999999999E93F3E1829533EB843C0B86182EF6F9E24C09A9999999999E93F3E1829533EB843C0C03A51E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Od	2.03411578109559965	288	287	288	01020000A034BF0D00040000007CF02BD09FA643C068550ABE186B28C09A9999999999E93F7CF02BD09FA643C0507C3BC6C48729C09A9999999999E93F7CF02BD09FA643C0C83F196542B229C09A9999999999E93FDE9E06145A2843C04086AE5559AB2BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	289	289	287	01020000A034BF0D00020000007CF02BD09FA643C0289D3316882B28C09A9999999999E93F7CF02BD09FA643C068550ABE186B28C09A9999999999E93F	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lf	1.00507820220856714	367	365	367	01020000A034BF0D000200000092957199842F4FC0407371D3FE5830C0000000000000084046EE2307832F4FC0B8F184A14B5A31C00000000000000840	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Od	3.40562176466340372	291	288	290	01020000A034BF0D0006000000DE9E06145A2843C04086AE5559AB2BC09A9999999999E93FDE9E06145A2843C0E833F8902F2B30C09A9999999999E93FDE9E06145A1843C0E833F8902F4B30C09A9999999999E93FDE9E06145A1843C0C089A55021FE30C09A9999999999E93F225BD42DAC1E43C048024184C50A31C09A9999999999E93F225BD42DAC1E43C040327BC7052B31C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Od	1.32166497457931276	292	288	291	01020000A034BF0D0003000000DE9E06145A2843C04086AE5559AB2BC09A9999999999E93F74683F4144C742C098AC910A02272AC09A9999999999E93FE080118D64A742C098AC910A02272AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Nn	3.97161348987304708	293	292	293	01020000A034BF0D000A000000A67E8FB9A41E43C0680F4036204A23C09A9999999999E93FA67E8FB9A41E43C0780AA5CB1A7B22C09A9999999999E93FA6164186B41D43C0786A6BFE597722C09A9999999999E93FA6164186B41D43C0788848FB343122C09A9999999999E93F769FFB5716DE42C0B0AB3242BC3221C09A9999999999E93F769FFB5716DE42C07067FBC9ED3120C09A9999999999E93F769FFB5716CE42C0E0CEF693DBE31FC09A9999999999E93F769FFB5716CE42C0B0A2B1BB977418C09A9999999999E93F001B489B83D442C060C64DA12D4118C09A9999999999E93F001B489B83D442C0407E2B428ED117C09A9999999999E93F	\N	\N
first_floor	\N	0.10867074331845572	294	294	292	01020000A034BF0D0002000000A67E8FB9A41E43C0D03A51E7C38123C09A9999999999E93FA67E8FB9A41E43C0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.4183696703509483	295	147	294	01020000A034BF0D000300000036815F3DB26C43C0F86BC2FEA5D625C09A9999999999E93FA67E8FB9A41E43C0B86182EF6F9E24C09A9999999999E93FA67E8FB9A41E43C0D03A51E7C38123C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Oe	2.06553053367635808	296	295	296	01020000A034BF0D000400000078E87E10CFB340C068550ABE186B28C09A9999999999E93F78E87E10CFB340C0507C3BC6C48729C09A9999999999E93F78E87E10CFB340C068C547C8EF8E29C09A9999999999E93F2A29A0372B3B41C030C8CC6460AC2BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	297	297	295	01020000A034BF0D000200000078E87E10CFB340C0289D3316882B28C09A9999999999E93F78E87E10CFB340C068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.16578744179471983	298	146	297	01020000A034BF0D000300000078E87E10CFB340C0186CC2FEA5D625C09A9999999999E93F78E87E10CFB340C04076020EDC0E27C09A9999999999E93F78E87E10CFB340C0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Oe	3.39835996331566248	299	296	298	01020000A034BF0D00060000002A29A0372B3B41C030C8CC6460AC2BC09A9999999999E93F2A29A0372B3B41C0E0548718B32B30C09A9999999999E93F2A29A0372B4B41C0E0548718B34B30C09A9999999999E93F2A29A0372B4B41C0C86816C99DFD30C09A9999999999E93FA018A184B04441C0DC89142F930A31C09A9999999999E93FA018A184B04441C048533AC48B2931C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Oe	1.32647447684009023	300	296	299	01020000A034BF0D00030000002A29A0372B3B41C030C8CC6460AC2BC09A9999999999E93F10F02ECE829C41C098AC910A02272AC09A9999999999E93F7C08011AA3BC41C098AC910A02272AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Oj	2.05902761104781007	301	300	301	01020000A034BF0D0004000000566393BE161540C068550ABE186B28C09A9999999999E93F566393BE161540C0587C3BC6C48729C09A9999999999E93F566393BE161540C0C0C647C8EF8E29C09A9999999999E93FF48BE788A21C3FC0303CC6B005AA2BC09A9999999999E93F	\N	\N
first_floor	\N	0.124150509797004815	302	302	300	01020000A034BF0D0002000000566393BE161540C0289D3316882B28C09A9999999999E93F566393BE161540C068550ABE186B28C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.1657874417946914	303	145	302	01020000A034BF0D0003000000566393BE161540C0286CC2FEA5D625C09A9999999999E93F566393BE161540C03876020EDC0E27C09A9999999999E93F566393BE161540C0289D3316882B28C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Oj	3.40645825950587167	304	301	303	01020000A034BF0D0006000000F48BE788A21C3FC0303CC6B005AA2BC09A9999999999E93FF48BE788A21C3FC044AF70201F2030C09A9999999999E93FF48BE788A2FC3EC044AF70201F4030C09A9999999999E93FF48BE788A2FC3EC01C25AAF5A1FE30C09A9999999999E93F6C3C570A65093FC094D51977640B31C09A9999999999E93F6C3C570A65093FC03C29AF39862A31C09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6Oj	1.34687394585084452	305	301	304	01020000A034BF0D0003000000F48BE788A21C3FC0303CC6B005AA2BC09A9999999999E93F5894C366ED553EC0F84C7E6C9B1C2AC09A9999999999E93FF0CC227D24163EC0F84C7E6C9B1C2AC09A9999999999E93F	\N	\N
first_floor	1BUg4a4jr0B9Q5NnDgB6NC	3.68741054065778773	306	305	306	01020000A034BF0D0009000000FEFCFB3B951F40C0680F4036204A23C09A9999999999E93F00FDFB3B951F40C078E80E2E742D22C09A9999999999E93F00FDFB3B951F40C01824F5EA5F2A22C09A9999999999E93FF45DAADB8AF140C0904077D812C51DC09A9999999999E93FF45DAADB8AF140C070D92B503F201CC09A9999999999E93F0A902C7257F740C0C0481A9CDAF11BC09A9999999999E93F86ED2B5F980A41C0C0481A9CDAF11BC09A9999999999E93F862BA340E41141C0D038D4A7392C1CC09A9999999999E93F0ACEA353A31E41C0D038D4A7392C1CC09A9999999999E93F	\N	\N
first_floor	\N	0.108670743318583618	307	307	305	01020000A034BF0D0002000000FEFCFB3B951F40C0183B51E7C38123C09A9999999999E93FFEFCFB3B951F40C0680F4036204A23C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	1.41836967035084127	308	144	307	01020000A034BF0D0003000000F4F457700FA33FC0286CC2FEA5D625C09A9999999999E93FFEFCFB3B951F40C0E06182EF6F9E24C09A9999999999E93FFEFCFB3B951F40C0183B51E7C38123C09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	3.99249344741750178	309	308	34	01020000A034BF0D0002000000609E71E1904427C090039A7CEE912DC09A9999999999E93F609E71E1904427C080B5B562C69525C09A9999999999E93F	\N	\N
first_floor	\N	3.63916967176426942	310	309	308	01020000A034BF0D0003000000F87D8A907CF124C05807A30C40F631C09A9999999999E93F609E71E1904427C0600F83CE86F22DC09A9999999999E93F609E71E1904427C090039A7CEE912DC09A9999999999E93F	\N	\N
first_floor	1mWTVVwiXDHQKYjSZ048h5	3.00850384461020193	311	310	167	01020000A034BF0D0002000000CBB62738E4E851C0308D033138A42DC09A9999999999E93FCBB62738E4E851C070E8FB28F59F27C09A9999999999E93F	\N	\N
first_floor	\N	3.50436618393977728	312	311	310	01020000A034BF0D000300000089855B35799E51C044E93BEB08DE31C09A9999999999E93FCBB62738E4E851C030E8716F16B02DC09A9999999999E93FCBB62738E4E851C0308D033138A42DC09A9999999999E93F	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lE	1.12003121719965826	313	312	313	01020000A034BF0D0002000000B692D5108DFD4DC000245E4E0E412CC00000000000000840D24212692D984DC070E450AF8FAB2AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lE	0.134848155992997931	314	313	314	01020000A034BF0D0002000000D24212692D984DC070E450AF8FAB2AC00000000000000840D24212692D984DC0880F09DE84662AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.19507681063849702	315	315	316	01020000A034BF0D0003000000E675459C60B34DC090D498BCE34728C00000000000000840E675459C60B34DC0A0AD67B4372B27C00000000000000840E675459C60B34DC0980705A102E425C00000000000000840	\N	\N
second_floor	\N	0.249668621059001339	316	317	315	01020000A034BF0D0002000000E675459C60B34DC0E8665D4DB8C728C00000000000000840E675459C60B34DC090D498BCE34728C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lE	0.898174840006691566	317	314	317	01020000A034BF0D0004000000D24212692D984DC0880F09DE84662AC00000000000000840E675459C60B34DC038433C11B8F929C00000000000000840E675459C60B34DC0D88D8E5564E429C00000000000000840E675459C60B34DC0E8665D4DB8C728C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.662015579741099258	318	316	318	01020000A034BF0D0003000000E675459C60B34DC0980705A102E425C000000000000008409A429D7F36EF4DC0980705A102E425C00000000000000840E2C9D754D2004EC068EA1A4C939D25C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	4.26006738142456953	319	318	319	01020000A034BF0D0004000000E2C9D754D2004EC068EA1A4C939D25C00000000000000840321489B53AC94EC068EA1A4C939D25C00000000000000840F609B211CA4B4FC078C1BEBCD0A727C00000000000000840AEC273CF07EC4FC078C1BEBCD0A727C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.9677270889019951	320	319	320	01020000A034BF0D0002000000AEC273CF07EC4FC078C1BEBCD0A727C00000000000000840BB735325F37350C078C1BEBCD0A727C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.70822139073615609	321	320	321	01020000A034BF0D0003000000BB735325F37350C078C1BEBCD0A727C00000000000000840E110B007F77450C0A8AAA3CFEFAF27C0000000000000084007215CFFDAE050C0A8AAA3CFEFAF27C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lg	1.03229707249457059	322	322	323	01020000A034BF0D000500000039548F320E1C51C024CA8A2B7DAA33C00000000000000840DBB4E2DFEE3551C024CA8A2B7DAA33C00000000000000840539E0911F73551C0047026F09DAA33C000000000000008409F8F6E829B3F51C0047026F09DAA33C000000000000008408B99DDEA2C5551C0B897E291E30034C00000000000000840	\N	\N
second_floor	\N	0.25	323	324	322	01020000A034BF0D000200000039548F320E0C51C024CA8A2B7DAA33C0000000000000084039548F320E1C51C024CA8A2B7DAA33C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048kN	7.1830583027692958	324	325	324	01020000A034BF0D000800000007215CFFDAE050C08842CD9CEABD2CC0000000000000084007215CFFDAE050C07869FEA496DA2DC0000000000000084007215CFFDAE050C018DC663684172EC0000000000000084065ED8AABDE9850C0903C786AB32B30C00000000000000840E7B74B6BDC9850C0AC9BD5B4620533C000000000000008408503F90823C250C024CA8A2B7DAA33C000000000000008405B2F89B178E850C024CA8A2B7DAA33C0000000000000084039548F320E0C51C024CA8A2B7DAA33C00000000000000840	\N	\N
second_floor	\N	0.190521208191000824	325	326	325	01020000A034BF0D000200000007215CFFDAE050C0A882E09D5E5C2CC0000000000000084007215CFFDAE050C08842CD9CEABD2CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.3367828797599941	326	321	326	01020000A034BF0D000300000007215CFFDAE050C0A8AAA3CFEFAF27C0000000000000084007215CFFDAE050C0B85BAF95B23F2BC0000000000000084007215CFFDAE050C0A882E09D5E5C2CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.35264495408100061	366	319	366	01020000A034BF0D0003000000AEC273CF07EC4FC078C1BEBCD0A727C00000000000000840AEC273CF07EC4FC0B85BAF95B23F2BC00000000000000840AEC273CF07EC4FC0A882E09D5E5C2CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lg	3.27866322730670579	327	323	327	01020000A034BF0D00060000008B99DDEA2C5551C0B897E291E30034C00000000000000840E7B196E055D951C0B897E291E30034C0000000000000084051D4E22AB9EB51C0140EB26856B733C00000000000000840AD7CEAD536F051C0140EB26856B733C0000000000000084029C01B1F371052C02400ED43553733C00000000000000840B9893B5B231252C02400ED43553733C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lg	0.908632209018369275	328	323	328	01020000A034BF0D00020000008B99DDEA2C5551C0B897E291E30034C0000000000000084039548F320E2C51C000AD1B735EA534C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.80000000000001137	329	321	329	01020000A034BF0D000200000007215CFFDAE050C0A8AAA3CFEFAF27C000000000000008403B548F320E5451C0A8AAA3CFEFAF27C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.889882495248997429	330	329	330	01020000A034BF0D00020000003B548F320E5451C0A8AAA3CFEFAF27C0000000000000084061EC4408028D51C0A8AAA3CFEFAF27C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.859309402660437427	331	330	331	01020000A034BF0D000300000061EC4408028D51C0A8AAA3CFEFAF27C00000000000000840F14DD1D4FB9F51C028B70634BE4728C00000000000000840F14DD1D4FB9F51C008321BE2052929C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.58714503115441952	332	330	332	01020000A034BF0D000300000061EC4408028D51C0A8AAA3CFEFAF27C00000000000000840416759B6498E51C098D3FF5EB2A527C000000000000008409D1B45160EF251C098D3FF5EB2A527C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.44685447965360581	333	332	333	01020000A034BF0D00050000009D1B45160EF251C098D3FF5EB2A527C000000000000008406DFF26F3334E52C018F20E46E1862AC0000000000000084079D6CA63715852C018F20E46E1862AC00000000000000840C9129CB2916052C090D498BCE3C72AC00000000000000840C9129CB2916052C090BCA57F49EC2AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.37496728516698852	334	333	334	01020000A034BF0D0002000000C9129CB2916052C090BCA57F49EC2AC00000000000000840C9129CB2916052C0F875EB3545AC2FC00000000000000840	\N	\N
second_floor	\N	0.609587404679501788	335	335	336	01020000A034BF0D0002000000C9129CB2919052C090BCA57F49EC2AC0000000000000084083DC7F2D95B752C090BCA57F49EC2AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.75	336	333	335	01020000A034BF0D0003000000C9129CB2916052C090BCA57F49EC2AC00000000000000840EBED9531FC6C52C090BCA57F49EC2AC00000000000000840C9129CB2919052C090BCA57F49EC2AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	4.05106571891685352	337	332	337	01020000A034BF0D00050000009D1B45160EF251C098D3FF5EB2A527C0000000000000084019CCCFD36C5C52C0C04FAA72BC5224C0000000000000084019CCCFD36C5C52C0A8C57491D6A921C000000000000008401DB0D345E36152C088A55501237E21C000000000000008401DB0D345E36152C0C8AB83DC21FE20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.65489527459048702	338	337	338	01020000A034BF0D00020000001DB0D345E36152C0C8AB83DC21FE20C000000000000008401DB0D345E36152C060A81CDBA65D1FC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	1.45346949794322655	339	339	340	01020000A034BF0D0004000000755CA765852252C0C8AB83DC21FE20C000000000000008409737A1E4EFFE51C0C8AB83DC21FE20C000000000000008405DFEC49CB4EE51C0C8AB83DC21FE20C0000000000000084041E5377191D151C0E8E21A80081520C00000000000000840	\N	\N
second_floor	\N	0.25	340	341	339	01020000A034BF0D0002000000755CA765853252C0C8AB83DC21FE20C00000000000000840755CA765852252C0C8AB83DC21FE20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.740104716575501698	341	337	341	01020000A034BF0D00030000001DB0D345E36152C0C8AB83DC21FE20C000000000000008405381ADE61A5652C0C8AB83DC21FE20C00000000000000840755CA765853252C0C8AB83DC21FE20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	1.56939305459496836	342	340	342	01020000A034BF0D000200000041E5377191D151C0E8E21A80081520C00000000000000840BDE1A681206D51C0E8E21A80081520C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	0.812508065997468498	343	340	343	01020000A034BF0D000300000041E5377191D151C0E8E21A80081520C000000000000008406D1D9B4B54EF51C02043025AE34D1EC000000000000008406D1D9B4B54EF51C0D088E7334CAF1DC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	0.452317861665538001	344	343	344	01020000A034BF0D00020000006D1D9B4B54EF51C0D088E7334CAF1DC000000000000008401D1F5481CC0352C0E06D57D8C8671CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	1.82371771601757882	345	343	345	01020000A034BF0D00040000006D1D9B4B54EF51C0D088E7334CAF1DC000000000000008409548DAE5F0E851C0503BDAD715491DC000000000000008409548DAE5F0E851C0E0B95E18678B17C00000000000000840A18F30A7BFDD51C0B02AC32D53D816C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	0.454891787035023754	346	345	346	01020000A034BF0D0002000000A18F30A7BFDD51C0B02AC32D53D816C000000000000008406D6DBFB4A2C051C0B02AC32D53D816C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	1.04999999600187266	347	346	347	01020000A034BF0D00030000006D6DBFB4A2C051C0B02AC32D53D816C000000000000008402DF9271B099F51C0B02AC32D53D816C00000000000000840398590816F7D51C0B02AC32D53D816C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lb	0.920346444524519858	348	348	349	01020000A034BF0D0005000000398590816F7D51C0D06BAE083BFC12C00000000000000840398590816F7D51C010A3374A9B6111C00000000000000840398590816F7D51C0507418EAB51011C00000000000000840118590816F7D51C0D07118EAB51011C00000000000000840118590816F7D51C0A0119B78979B0EC00000000000000840	\N	\N
second_floor	\N	0.0899999999993923439	349	350	348	01020000A034BF0D0002000000398590816F7D51C080F870FE635813C00000000000000840398590816F7D51C0D06BAE083BFC12C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	0.874935855285499997	350	347	350	01020000A034BF0D0003000000398590816F7D51C0B02AC32D53D816C00000000000000840398590816F7D51C040C1E7BC03F314C00000000000000840398590816F7D51C080F870FE635813C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lu	0.942059195305055441	351	351	352	01020000A034BF0D0005000000D33D983A013851C0D06BAE083BFC12C00000000000000840D33D983A013851C010A3374A9B6111C00000000000000840D33D983A013851C0F033A132F03E11C000000000000008405F33C196903A51C030DB1170FA1511C000000000000008405F33C196903A51C0E03EA86C0E910EC00000000000000840	\N	\N
second_floor	\N	0.0899999999993923439	352	353	351	01020000A034BF0D0002000000D33D983A013851C080F870FE635813C00000000000000840D33D983A013851C0D06BAE083BFC12C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	1.70199870912001217	353	347	353	01020000A034BF0D0006000000398590816F7D51C0B02AC32D53D816C00000000000000840F110F9E7D55B51C0B02AC32D53D816C00000000000000840AD8D2C802B5451C0B02AC32D53D816C00000000000000840D33D983A013851C0202D7ED4AE1515C00000000000000840D33D983A013851C040C1E7BC03F314C00000000000000840D33D983A013851C080F870FE635813C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lc	0.920346444524489327	354	354	355	01020000A034BF0D00050000006D6DBFB4A2C051C0D06BAE083BFC12C000000000000008406D6DBFB4A2C051C010A3374A9B6111C000000000000008406D6DBFB4A2C051C0D07318EAB51011C000000000000008404F6DBFB4A2C051C0F07118EAB51011C000000000000008404F6DBFB4A2C051C060119B78979B0EC00000000000000840	\N	\N
second_floor	\N	0.0899999999993923439	355	356	354	01020000A034BF0D00020000006D6DBFB4A2C051C080F870FE635813C000000000000008406D6DBFB4A2C051C0D06BAE083BFC12C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	0.874935855285499997	356	346	356	01020000A034BF0D00030000006D6DBFB4A2C051C0B02AC32D53D816C000000000000008406D6DBFB4A2C051C040C1E7BC03F314C000000000000008406D6DBFB4A2C051C080F870FE635813C00000000000000840	\N	\N
second_floor	\N	0.0225805231300776586	357	357	358	01020000A034BF0D0002000000D34E483C5E0552C080F870FE635813C000000000000008401D5111D6630652C0E0D3E0610A4813C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	1.13135645983353728	358	345	357	01020000A034BF0D0005000000A18F30A7BFDD51C0B02AC32D53D816C000000000000008406DE1564E3CE251C0000E5EBB889016C00000000000000840ABCB273A3C0152C0206A4FFE89A014C00000000000000840ABCB273A3C0152C0002B7920849A13C00000000000000840D34E483C5E0552C080F870FE635813C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048li	0.311172288924506435	359	359	360	01020000A034BF0D00030000006753DA6F690752C080F870FE635813C000000000000008408988E9A0BB1352C0904A640F871D14C00000000000000840898BBC2C391652C0904A640F871D14C00000000000000840	\N	\N
second_floor	\N	0.0225805231300776586	360	358	359	01020000A034BF0D00020000001D5111D6630652C0E0D3E0610A4813C000000000000008406753DA6F690752C080F870FE635813C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lZ	0.936812411220175556	361	361	362	01020000A034BF0D00050000001D5111D6630652C02069AE083BFC12C000000000000008401D5111D6630652C060A0374A9B6111C000000000000008401D5111D6630652C06070078DC23911C00000000000000840475BE879D40352C0001378CACC1011C00000000000000840475BE879D40352C060AB1840CD9B0EC00000000000000840	\N	\N
second_floor	\N	0.074033158971985813	362	358	361	01020000A034BF0D00020000001D5111D6630652C0E0D3E0610A4813C000000000000008401D5111D6630652C02069AE083BFC12C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.60279257407976017	363	320	363	01020000A034BF0D0003000000BB735325F37350C078C1BEBCD0A727C0000000000000084099AA3DB0479850C0880A6D652C8526C0000000000000084099AA3DB0479850C0F070D3CB92EB20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lf	2.57763976583958332	364	364	365	01020000A034BF0D0005000000AEC273CF07EC4FC0E849C9C798C22CC00000000000000840AEC273CF07EC4FC0F04E64329E912DC00000000000000840D23CD6B41FE84FC06066DA9C3EA12DC00000000000000840F2E190901FE84FC0E8ED6ED4A3CF2DC0000000000000084092957199842F4FC0407371D3FE5830C00000000000000840	\N	\N
second_floor	\N	0.199662503876993469	365	366	364	01020000A034BF0D0002000000AEC273CF07EC4FC0A882E09D5E5C2CC00000000000000840AEC273CF07EC4FC0E849C9C798C22CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lf	2.44402523131375293	368	367	368	01020000A034BF0D000300000046EE2307832F4FC0B8F184A14B5A31C000000000000008406A2EAB61AB534EC0747176ECFA1133C0000000000000084002377E00BD514EC0747176ECFA1133C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lf	1.63523659334367766	369	367	369	01020000A034BF0D000500000046EE2307832F4FC0B8F184A14B5A31C0000000000000084092032CB724304FC084AB7B098F5B31C00000000000000840CED4E12623304FC06425F029925B32C00000000000000840CA0EAB76EE344FC0E01B7B05296532C0000000000000084066B76A90ED344FC03C09A0E36BF832C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lf	0.691453692809355314	370	365	370	01020000A034BF0D000300000092957199842F4FC0407371D3FE5830C0000000000000084042BB83FCD6FF4EC0487D2B3347F32FC000000000000008404A4575C6C2EA4EC0487D2B3347F32FC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.66046322993175144	371	318	371	01020000A034BF0D0005000000E2C9D754D2004EC068EA1A4C939D25C000000000000008406E93B35419AB4DC098108A4BAF4624C000000000000008406E93B35419AB4DC07808F2107FA721C000000000000008403AF6335C46984DC0A893F32E335C21C000000000000008403AF6335C46984DC01084700FA3F820C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	1.46276510858943487	372	372	373	01020000A034BF0D0004000000A2A11379631F4EC01084700FA3F820C000000000000008405EEB1F7B8E664EC01084700FA3F820C000000000000008407A4584B66D864EC01084700FA3F820C000000000000008400A196671F6C14EC0C035E923800A20C00000000000000840	\N	\N
second_floor	\N	0.24557595177998337	373	374	372	01020000A034BF0D000200000082D7AE70F4FF4DC01084700FA3F820C00000000000000840A2A11379631F4EC01084700FA3F820C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.810000000000002274	374	371	374	01020000A034BF0D00030000003AF6335C46984DC01084700FA3F820C00000000000000840C68DA26EC9B84DC01084700FA3F820C0000000000000084082D7AE70F4FF4DC01084700FA3F820C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	1.55894712300903393	375	373	375	01020000A034BF0D00020000000A196671F6C14EC0C035E923800A20C000000000000008403ADBB40582894FC0C035E923800A20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	0.80622524884276614	376	373	376	01020000A034BF0D00030000000A196671F6C14EC0C035E923800A20C000000000000008407E87972A08874EC010DF5D118E3D1EC000000000000008407E87972A08874EC090AF1EB1B49E1DC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	1.8189075880607759	377	376	377	01020000A034BF0D00060000007E87972A08874EC090AF1EB1B49E1DC0000000000000084046341E279A904EC05049E9CC24521DC0000000000000084046341E279A904EC05049E9CC24521CC00000000000000840C6B3B7C033924EC0504D1D0058451CC00000000000000840C6B3B7C033924EC0D0EDF74D105A17C000000000000008403637CF3EBAA54EC050D23B5DDCBD16C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	0.500186748687241334	378	377	378	01020000A034BF0D00020000003637CF3EBAA54EC050D23B5DDCBD16C00000000000000840C2F75E5DC0E54EC050D23B5DDCBD16C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	1.0499999960019295	379	378	379	01020000A034BF0D0003000000C2F75E5DC0E54EC050D23B5DDCBD16C0000000000000084022E08D90F3284FC050D23B5DDCBD16C0000000000000084032C8BCC3266C4FC050D23B5DDCBD16C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lo	0.961856137703103187	380	380	381	01020000A034BF0D0005000000A681797AB7F54FC040599F9BB6E112C00000000000000840B681797AB7F54FC0809028DD164711C00000000000000840B2FD58403CF74FC0C0B02CAEF03A11C000000000000008401A9627C298F04FC00074A1BCD40511C000000000000008401A9627C298F04FC0808FD5649B470EC00000000000000840	\N	\N
second_floor	\N	0.090000000000358682	381	382	380	01020000A034BF0D0002000000A281797AB7F54FC030EA6191DF3D13C00000000000000840A681797AB7F54FC040599F9BB6E112C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	1.68596100092194856	382	379	382	01020000A034BF0D000600000032C8BCC3266C4FC050D23B5DDCBD16C000000000000008409AB0EBF659AF4FC050D23B5DDCBD16C000000000000008409E158C6415BC4FC050D23B5DDCBD16C000000000000008409281797AB7F54FC0C072D0ADCBF014C000000000000008409281797AB7F54FC0F0B2D84F7FD814C00000000000000840A281797AB7F54FC030EA6191DF3D13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048ln	0.952910487115769422	383	383	384	01020000A034BF0D000500000046C8BCC3266C4FC040599F9BB6E112C0000000000000084056C8BCC3266C4FC0809028DD164711C0000000000000084072BBBE1935714FC0C0F7182DA41E11C000000000000008405EC8BCC3266C4FC0205F097D31F610C000000000000008405EC8BCC3266C4FC040B905E4E1660EC00000000000000840	\N	\N
second_floor	\N	0.090000000000358682	384	385	383	01020000A034BF0D000200000042C8BCC3266C4FC030EA6191DF3D13C0000000000000084046C8BCC3266C4FC040599F9BB6E112C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	0.874987778830501384	385	379	385	01020000A034BF0D000300000032C8BCC3266C4FC050D23B5DDCBD16C0000000000000084032C8BCC3266C4FC0F0B2D84F7FD814C0000000000000084042C8BCC3266C4FC030EA6191DF3D13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lq	0.952910487115782523	386	386	387	01020000A034BF0D0005000000D6F75E5DC0E54EC040599F9BB6E112C00000000000000840EAF75E5DC0E54EC0809028DD164711C00000000000000840FAEA60B3CEEA4EC010F8182DA41E11C00000000000000840E6F75E5DC0E54EC0605F097D31F610C00000000000000840E6F75E5DC0E54EC0C0B805E4E1660EC00000000000000840	\N	\N
second_floor	\N	0.090000000000358682	387	388	386	01020000A034BF0D0002000000D2F75E5DC0E54EC030EA6191DF3D13C00000000000000840D6F75E5DC0E54EC040599F9BB6E112C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	0.874987778830501384	388	378	388	01020000A034BF0D0003000000C2F75E5DC0E54EC050D23B5DDCBD16C00000000000000840C2F75E5DC0E54EC0F0B2D84F7FD814C00000000000000840D2F75E5DC0E54EC030EA6191DF3D13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lB	0.952486239310288418	389	389	390	01020000A034BF0D0007000000FAF10F4A34644EC040599F9BB6E112C00000000000000840FEF10F4A34644EC070CC836B12CA11C00000000000000840B60F302A8D624EC010BA846CD9BC11C00000000000000840BA0F302A8D624EC0709028DD164711C00000000000000840AA8E9AE601664EC00099D4F9702B11C0000000000000084026C4F309175E4EC0E0449E141AEC10C0000000000000084026C4F309175E4EC0C0EDDBB4107B0EC00000000000000840	\N	\N
second_floor	\N	0.090000000000358682	390	391	389	01020000A034BF0D0002000000FAF10F4A34644EC030EA6191DF3D13C00000000000000840FAF10F4A34644EC040599F9BB6E112C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	1.0870239143252507	391	377	391	01020000A034BF0D00060000003637CF3EBAA54EC050D23B5DDCBD16C00000000000000840A20F302A8DA24EC0B09542B873A416C000000000000008406E71A9E3CD654EC020A40D8479BE14C000000000000008407671A9E3CD654EC040FF09E051C713C00000000000000840F6F10F4A34644EC030033E1385BA13C00000000000000840FAF10F4A34644EC030EA6191DF3D13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l$	0.438053546813286288	392	376	392	01020000A034BF0D00020000007E87972A08874EC090AF1EB1B49E1DC00000000000000840662FF341625F4EC0D0EEFB6B85611CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.580499591417009242	393	371	393	01020000A034BF0D00020000003AF6335C46984DC01084700FA3F820C000000000000008403AF6335C46984DC0401FBFA2D79E1FC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.26200636282128364	394	316	394	01020000A034BF0D0004000000E675459C60B34DC0980705A102E425C000000000000008408226E87938914DC0980705A102E425C00000000000000840724E5296058E4DC068A7AD1237D725C00000000000000840F6B180612A134CC068A7AD1237D725C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.3199890916921504	395	394	395	01020000A034BF0D0002000000F6B180612A134CC068A7AD1237D725C0000000000000084076BF72FA34EA4AC068A7AD1237D725C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.45180680600108891	396	395	396	01020000A034BF0D000300000076BF72FA34EA4AC068A7AD1237D725C00000000000000840424BE702AE954AC068A7AD1237D725C000000000000008402230B0040C4E4AC0E0138A0BBFF526C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.523780672107459488	397	396	397	01020000A034BF0D00020000002230B0040C4E4AC0E0138A0BBFF526C000000000000008406AA776C5A31E4AC0C836700860B327C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.28957874988998356	398	397	398	01020000A034BF0D00020000006AA776C5A31E4AC0C836700860B327C00000000000000840FA74D8DA927948C0C836700860B327C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15905238501267149	399	398	399	01020000A034BF0D0002000000FA74D8DA927948C0C836700860B327C000000000000008408277BC0637E547C0C836700860B327C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.16094761498732169	400	399	400	01020000A034BF0D00020000008277BC0637E547C0C836700860B327C00000000000000840D21849189D5047C0C836700860B327C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6LG	3.9233383377832256	401	401	402	01020000A034BF0D0006000000D21849189D5047C0A8FCC28A664523C00000000000000840D21849189D5047C058F72720617622C00000000000000840C2EB967AAD5047C098ABF0961F7622C00000000000000840C2EB967AAD5047C07821C90BFC2822C000000000000008401AFAC32C4B9847C028E81443850A21C000000000000008401AFAC32C4B9847C090237F4BD4C617C00000000000000840	\N	\N
second_floor	\N	0.114707788247855547	402	403	401	01020000A034BF0D0002000000D21849189D5047C0A03A7185218023C00000000000000840D21849189D5047C0A8FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.10008630144700703	403	400	403	01020000A034BF0D0003000000D21849189D5047C0C836700860B327C00000000000000840D21849189D5047C09061A28DCD9C24C00000000000000840D21849189D5047C0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.0390523850126669458	404	400	404	01020000A034BF0D0002000000D21849189D5047C0C836700860B327C00000000000000840EADD226D9D4B47C0C836700860B327C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.854913698552337564	405	404	405	01020000A034BF0D0002000000EADD226D9D4B47C0C836700860B327C0000000000000084046C63E9D2FDE46C0C836700860B327C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.432797315168529095	406	405	406	01020000A034BF0D000200000046C63E9D2FDE46C0C836700860B327C00000000000000840387FAF7E03B746C0901A338EAF1627C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Ml	3.95795003603080264	407	407	408	01020000A034BF0D000A000000387FAF7E03B746C058FCC28A664523C00000000000000840387FAF7E03B746C060F72720617622C0000000000000084046AC611CF3B646C098ABF0961F7622C0000000000000084046AC611CF3B646C03021C90BFC2822C000000000000008408C913B58F27746C048B630FBF82C21C000000000000008408C913B58F27746C0D84B81AC2F3120C0000000000000084096D259B35A6846C000A0F431A2E51FC0000000000000084096D259B35A6846C0B07EFB3D107418C00000000000000840685F59C0606E46C02018FFD5DF4318C00000000000000840685F59C0606E46C07018599A79CE17C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	408	409	407	01020000A034BF0D0002000000387FAF7E03B746C0A03A7185218023C00000000000000840387FAF7E03B746C058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.7940523850120087	409	406	409	01020000A034BF0D0003000000387FAF7E03B746C0901A338EAF1627C00000000000000840387FAF7E03B746C09061A28DCD9C24C00000000000000840387FAF7E03B746C0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.10579208869931866	410	406	410	01020000A034BF0D0003000000387FAF7E03B746C0901A338EAF1627C00000000000000840AA2CA503966446C058D009A2F9CC25C00000000000000840085C4E6B9D4B45C058D009A2F9CC25C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Mg	5.12462571842970682	411	411	412	01020000A034BF0D000B000000085C4E6B9D4B45C058FCC28A664523C00000000000000840085C4E6B9D4B45C068D59182BA2822C00000000000000840085C4E6B9D4B45C0889FD399B3DF21C00000000000000840D2F5B3AACED444C0B0066A97780420C00000000000000840D2F5B3AACED444C0803875915E111EC000000000000008408A14399620E544C0C0424C35CF8E1DC000000000000008408A14399620E544C0F0DBA33AE3CA1AC00000000000000840E2F6044670DE44C0B0EE02B960951AC00000000000000840E2F6044670DE44C000EF5C7DFA1F1AC000000000000008408E522D8DDA6A45C0A0111A44A8BC15C000000000000008408E522D8DDA6A45C0B0E176D36AB215C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	412	413	411	01020000A034BF0D0002000000085C4E6B9D4B45C0A03A7185218023C00000000000000840085C4E6B9D4B45C058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144698998	413	410	413	01020000A034BF0D0003000000085C4E6B9D4B45C058D009A2F9CC25C00000000000000840085C4E6B9D4B45C09061A28DCD9C24C00000000000000840085C4E6B9D4B45C0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	4.29999999999999716	414	410	414	01020000A034BF0D0002000000085C4E6B9D4B45C058D009A2F9CC25C00000000000000840A2F5E704372543C058D009A2F9CC25C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Mf	3.18415612345224641	415	415	416	01020000A034BF0D0009000000A2F5E704372543C058FCC28A664523C00000000000000840A2F5E704372543C068D59182BA2822C00000000000000840A2F5E704372543C0F03F04E37F1120C0000000000000084082D60EB5A52843C070BC6822C50320C0000000000000084082D60EB5A52843C080165DAB600F1EC00000000000000840CAB789C9531843C0C020344FD18C1DC00000000000000840CAB789C9531843C0D0507400A2CB1AC000000000000008400C525BF8121F43C0C07EE789A8951AC000000000000008400C525BF8121F43C0A036C52A09261AC00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	416	417	415	01020000A034BF0D0002000000A2F5E704372543C0A03A7185218023C00000000000000840A2F5E704372543C058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144698998	417	414	417	01020000A034BF0D0003000000A2F5E704372543C058D009A2F9CC25C00000000000000840A2F5E704372543C09061A28DCD9C24C00000000000000840A2F5E704372543C0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.70134294243050022	418	414	418	01020000A034BF0D0002000000A2F5E704372543C058D009A2F9CC25C000000000000008402673E369714B41C058D009A2F9CC25C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Ma	3.23097174319741232	419	419	420	01020000A034BF0D00090000002673E369714B41C058FCC28A664523C000000000000008402673E369714B41C068D59182BA2822C000000000000008402673E369714B41C000E2A2F9694520C00000000000000840B25782101F3B41C030741E94200420C00000000000000840B25782101F3B41C00086C88E17101EC000000000000008406A7607FC704B41C040909F32888D1DC000000000000008406A7607FC704B41C050E1081DEBCA1AC0000000000000084070060287BF4441C08061DD745F951AC0000000000000084070060287BF4441C07081695DA1201AC00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	420	421	419	01020000A034BF0D00020000002673E369714B41C0A03A7185218023C000000000000008402673E369714B41C058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144698998	421	418	421	01020000A034BF0D00030000002673E369714B41C058D009A2F9CC25C000000000000008402673E369714B41C09061A28DCD9C24C000000000000008402673E369714B41C0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.00464200410081617	422	418	422	01020000A034BF0D00020000002673E369714B41C058D009A2F9CC25C00000000000000840A28CEF4DD9CA40C058D009A2F9CC25C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.39535799589918952	423	422	423	01020000A034BF0D0002000000A28CEF4DD9CA40C058D009A2F9CC25C00000000000000840E47F606D7C303EC058D009A2F9CC25C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MZ	5.18212757021347681	424	424	425	01020000A034BF0D000C000000E47F606D7C303EC058FCC28A664523C00000000000000840E47F606D7C303EC068D59182BA2822C00000000000000840E47F606D7C303EC0207B3C9303DF21C000000000000008406083EFECED1D3FC028741E94200420C000000000000008406083EFECED1D3FC0405F0AD9720F1EC00000000000000840F045E5154AFD3EC08069E17CE38C1DC00000000000000840F045E5154AFD3EC020C6D6F842CA1AC00000000000000840DC6753BCC60A3FC0703E1E5F50941AC00000000000000840DC6753BCC60A3FC090112E2459251AC0000000000000084000714B1FBF8C3FC000ED4D98771D18C000000000000008400AC1ECAFF11740C0B0A81596E69015C000000000000008400AC1ECAFF11740C0C010C4DDC78B15C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	425	426	424	01020000A034BF0D0002000000E47F606D7C303EC0A03A7185218023C00000000000000840E47F606D7C303EC058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144698998	426	423	426	01020000A034BF0D0003000000E47F606D7C303EC058D009A2F9CC25C00000000000000840E47F606D7C303EC09061A28DCD9C24C00000000000000840E47F606D7C303EC0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.10308066398400362	427	423	427	01020000A034BF0D0003000000E47F606D7C303EC058D009A2F9CC25C000000000000008409CC3B1EA53FC3BC058D009A2F9CC25C00000000000000840F45BF6C287593BC0A89F80F1911227C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.401738954249359848	428	427	428	01020000A034BF0D0002000000F45BF6C287593BC0A89F80F1911227C00000000000000840AC71F9CBCE103BC038747ADF03A427C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.876277176621883314	429	428	429	01020000A034BF0D0002000000AC71F9CBCE103BC038747ADF03A427C00000000000000840309F81187B303AC038747ADF03A427C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.0396504845615908152	430	429	430	01020000A034BF0D0002000000309F81187B303AC038747ADF03A427C00000000000000840C428C38F54263AC038747ADF03A427C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Mz	3.91833833780180285	431	431	432	01020000A034BF0D0006000000C428C38F54263AC088FDC28A664523C00000000000000840C428C38F54263AC070F72720617622C00000000000000840248327CB33263AC038ACF0961F7622C00000000000000840248327CB33263AC0D821C90BFC2822C00000000000000840C066CD66F89639C008E91443850A21C00000000000000840C066CD66F89639C030BED003F3CB17C00000000000000840	\N	\N
second_floor	\N	0.114707788247457643	432	433	431	01020000A034BF0D0002000000C428C38F54263AC0A03A7185218023C00000000000000840C428C38F54263AC088FDC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.07008630144700589	433	430	433	01020000A034BF0D0003000000C428C38F54263AC038747ADF03A427C00000000000000840C428C38F54263AC09061A28DCD9C24C00000000000000840C428C38F54263AC0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.16034951543841203	434	430	434	01020000A034BF0D0002000000C428C38F54263AC038747ADF03A427C00000000000000840FC6B4EE547FD38C038747ADF03A427C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15965048456159536	435	434	435	01020000A034BF0D0002000000FC6B4EE547FD38C038747ADF03A427C000000000000008407070A40A69D437C038747ADF03A427C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Mu	3.95762947996184522	436	436	437	01020000A034BF0D000A0000007070A40A69D437C058FCC28A664523C000000000000008407070A40A69D437C070F72720617622C0000000000000084044CA084648D437C018ABF0961F7622C0000000000000084044CA084648D437C0C021C90BFC2822C00000000000000840C8AEFDEA485637C0C8EAB255FD2C21C00000000000000840C8AEFDEA485637C0404666F63C3020C000000000000008405871F313A53537C0C096A390EADD1FC000000000000008405871F313A53537C0605C789CEB7718C000000000000008403C1A9971234337C0D0B8E125F24118C000000000000008403C1A9971234337C0700827C498D317C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	437	438	436	01020000A034BF0D00020000007070A40A69D437C0A03A7185218023C000000000000008407070A40A69D437C058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.07008630144700589	438	435	438	01020000A034BF0D00030000007070A40A69D437C038747ADF03A427C000000000000008407070A40A69D437C09061A28DCD9C24C000000000000008407070A40A69D437C0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.32389973592249532	439	435	439	01020000A034BF0D00020000007070A40A69D437C038747ADF03A427C000000000000008401478CFF27D8134C038747ADF03A427C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.503508032058706312	440	439	440	01020000A034BF0D00020000001478CFF27D8134C038747ADF03A427C00000000000000840645D6EE8582634C0D83EB8CAB9ED26C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Mt	3.9622646719017891	441	441	442	01020000A034BF0D000A000000645D6EE8582634C058FCC28A664523C00000000000000840645D6EE8582634C078F72720617622C000000000000008400C030AAD792634C028ACF0961F7622C000000000000008400C030AAD792634C0B820C90BFC2822C00000000000000840D49034925FA434C030057441302D21C00000000000000840D49034925FA434C0A86027E26F3020C0000000000000084044CE3E6903C534C090CB256850DE1FC0000000000000084044CE3E6903C534C09027F6C4857718C00000000000000840AC62367FA0B734C03079D41CFA4118C00000000000000840AC62367FA0B734C0E030C80282CE17C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	442	443	441	01020000A034BF0D0002000000645D6EE8582634C0A03A7185218023C00000000000000840645D6EE8582634C058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.71405235759640107	443	440	443	01020000A034BF0D0003000000645D6EE8582634C0D83EB8CAB9ED26C00000000000000840645D6EE8582634C09061A28DCD9C24C00000000000000840645D6EE8582634C0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.43360238917515526	444	440	444	01020000A034BF0D0003000000645D6EE8582634C0D83EB8CAB9ED26C00000000000000840242617D4F89533C058D009A2F9CC25C00000000000000840302A3BB525F332C058D009A2F9CC25C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.32205279391750707	445	444	445	01020000A034BF0D0002000000302A3BB525F332C058D009A2F9CC25C0000000000000084024B4F1A7B3A030C058D009A2F9CC25C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.9178310959694298	446	445	446	01020000A034BF0D000500000024B4F1A7B3A030C058D009A2F9CC25C0000000000000084018027883EFD92AC058D009A2F9CC25C00000000000000840005430A274C52AC0707E518374E125C00000000000000840409B7122B0CE29C0707E518374E125C0000000000000084070E5CB16888E29C0A0C8AB774CA125C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.93730044359985509	447	446	447	01020000A034BF0D000300000070E5CB16888E29C0A0C8AB774CA125C00000000000000840309E8A964C8526C0A0C8AB774CA125C00000000000000840F8788019788324C0D8EDB5F420A327C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.947386558761976971	448	447	448	01020000A034BF0D0002000000F8788019788324C0D8EDB5F420A327C00000000000000840005EA33F689E22C0D8EDB5F420A327C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.4578409906098031	449	448	449	01020000A034BF0D0003000000005EA33F689E22C0D8EDB5F420A327C00000000000000840307E2672317617C0D8EDB5F420A327C0000000000000084060347A8B256C17C0F0C85F011B9E27C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.667420586134525706	450	449	450	01020000A034BF0D000200000060347A8B256C17C0F0C85F011B9E27C0000000000000084070B4213EB5C014C0F0C85F011B9E27C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.62163611922146345	451	450	451	01020000A034BF0D000200000070B4213EB5C014C0F0C85F011B9E27C0000000000000084080DCB2204E8804C0F0C85F011B9E27C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	5.61584703285852438	452	451	452	01020000A034BF0D000800000080DCB2204E8804C0F0C85F011B9E27C0000000000000084040EC9874CF43FCBF582FC667810426C000000000000008400010C12DEE49CFBF582FC667810426C00000000000000840001AE6296770CABF582FC667810426C00000000000000840006C7057943EE53F3090A785D64624C00000000000000840006C7057943EE53F3871BE76A2A421C00000000000000840004C1A109A22E93F38D3331B626621C00000000000000840004C1A109A22E93F28897F828FFD20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	1.42077893475734118	453	453	454	01020000A034BF0D00040000000010C12DEE49CFBF28897F828FFD20C000000000000008400023C0181341E6BF28897F828FFD20C00000000000000840402BE47CB0A0F0BF28897F828FFD20C0000000000000084040BDD35CC1B5F7BFE8968166ED1A20C00000000000000840	\N	\N
second_floor	\N	0.25	454	455	453	01020000A034BF0D00020000000000DE473AC2763F28897F828FFD20C000000000000008400010C12DEE49CFBF28897F828FFD20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.779917529860995273	455	452	455	01020000A034BF0D0003000000004C1A109A22E93F28897F828FFD20C000000000000008400037BF033838DD3F28897F828FFD20C000000000000008400000DE473AC2763F28897F828FFD20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	1.64072386883400156	456	454	456	01020000A034BF0D000200000040BDD35CC1B5F7BFE8968166ED1A20C0000000000000084080235D8414FB08C0E8968166ED1A20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	0.833029560556820092	457	454	457	01020000A034BF0D000300000040BDD35CC1B5F7BFE8968166ED1A20C0000000000000084080F5B51E2CD5F0BFF0BB7B7DB57D1EC0000000000000084080F5B51E2CD5F0BFE088E89125971DC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	1.78292440942558983	458	457	458	01020000A034BF0D000400000080F5B51E2CD5F0BFE088E89125971DC00000000000000840C03593FF666FF2BFD038B1D996301DC00000000000000840C03593FF666FF2BF802C0BADBDAB17C0000000000000084000172739EF64F5BF4034A69E5BEE16C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	0.4276658036609291	459	458	459	01020000A034BF0D000200000000172739EF64F5BF4034A69E5BEE16C00000000000000840C08C2C52A73CFCBF4034A69E5BEE16C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	1.04999999600188687	460	459	460	01020000A034BF0D0003000000C08C2C52A73CFCBF4034A69E5BEE16C00000000000000840C0CA04DC865102C04034A69E5BEE16C00000000000000840004DF30EBA8406C04034A69E5BEE16C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lL	0.954043667811909302	461	461	462	01020000A034BF0D00050000008060E6C8A14C0FC0208876BC630013C000000000000008408060E6C8A14C0FC060BFFFFDC36511C000000000000008408060E6C8A14C0FC0803FF478093611C0000000000000084040A9C743B6FA0EC0E0E364B6130D11C0000000000000084040A9C743B6FA0EC080A98C83D4800EC00000000000000840	\N	\N
second_floor	\N	0.0899999999999323563	462	463	461	01020000A034BF0D00020000008060E6C8A14C0FC0301739B28C5C13C000000000000008408060E6C8A14C0FC0208876BC630013C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	1.72945421111938025	463	460	463	01020000A034BF0D0006000000004DF30EBA8406C04034A69E5BEE16C0000000000000084040D2E141EDB70AC04034A69E5BEE16C00000000000000840E0B61077B8BD0BC04034A69E5BEE16C000000000000008408060E6C8A14C0FC0705FBBF5E62615C000000000000008408060E6C8A14C0FC0F0DFAF702CF714C000000000000008408060E6C8A14C0FC0301739B28C5C13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lM	0.945085081031279639	464	464	465	01020000A034BF0D0005000000004DF30EBA8406C0208876BC630013C00000000000000840004DF30EBA8406C060BFFFFDC36511C00000000000000840004DF30EBA8406C0008FE09DDE1411C00000000000000840804EF30EBA8406C0408EE09DDE1411C00000000000000840804EF30EBA8406C0C05495B43E710EC00000000000000840	\N	\N
second_floor	\N	0.0899999999999323563	465	466	464	01020000A034BF0D0002000000004DF30EBA8406C0301739B28C5C13C00000000000000840004DF30EBA8406C0208876BC630013C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	0.892390913162003585	466	460	466	01020000A034BF0D0003000000004DF30EBA8406C04034A69E5BEE16C00000000000000840004DF30EBA8406C0F0DFAF702CF714C00000000000000840004DF30EBA8406C0301739B28C5C13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lJ	0.94508508103123845	467	467	468	01020000A034BF0D0005000000C08C2C52A73CFCBF208876BC630013C00000000000000840C08C2C52A73CFCBF60BFFFFDC36511C00000000000000840C08C2C52A73CFCBF908EE09DDE1411C00000000000000840008E2C52A73CFCBF408EE09DDE1411C00000000000000840008E2C52A73CFCBFC05495B43E710EC00000000000000840	\N	\N
second_floor	\N	0.0899999999999323563	468	469	467	01020000A034BF0D0002000000C08C2C52A73CFCBF301739B28C5C13C00000000000000840C08C2C52A73CFCBF208876BC630013C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	0.892390913162003585	469	459	469	01020000A034BF0D0003000000C08C2C52A73CFCBF4034A69E5BEE16C00000000000000840C08C2C52A73CFCBFF0DFAF702CF714C00000000000000840C08C2C52A73CFCBF301739B28C5C13C00000000000000840	\N	\N
second_floor	\N	0.0429537524212110847	470	470	471	01020000A034BF0D000300000000B15DBEEEBAE8BF301739B28C5C13C0000000000000084000B15DBEEEBAE8BF604FF6650A5913C000000000000008400092B9B7F7D5E7BF80CB21856B3C13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	1.12614127079994719	471	458	470	01020000A034BF0D000600000000172739EF64F5BF4034A69E5BEE16C0000000000000084000864FEC40D6F3BF1050700BB08A16C00000000000000840808E2A5D2E73E9BF60C0019C85C314C00000000000000840808E2A5D2E73E9BFD0E0F8B5A13214C0000000000000084000B15DBEEEBAE8BF20451FC2991B14C0000000000000084000B15DBEEEBAE8BF301739B28C5C13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lS	0.961965972508309508	472	472	473	01020000A034BF0D00050000000092B9B7F7D5E7BF208876BC630013C000000000000008400092B9B7F7D5E7BF60BFFFFDC36511C000000000000008400092B9B7F7D5E7BFE01F3BF3A63311C00000000000000840007834CCA51DE7BFA07CCAB59C1C11C00000000000000840007834CCA51DE7BF0078C184C2610EC00000000000000840	\N	\N
second_floor	\N	0.0586234430819274621	473	471	472	01020000A034BF0D00020000000092B9B7F7D5E7BF80CB21856B3C13C000000000000008400092B9B7F7D5E7BF208876BC630013C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	0.355302154765635703	474	474	475	01020000A034BF0D00030000008034FF4EEED4E6BF301739B28C5C13C0000000000000084000408109F4EAE0BFB0D5E8FACB1914C00000000000000840002DA4B8CFD2DBBFB0D5E8FACB1914C00000000000000840	\N	\N
second_floor	\N	0.0443731523340138781	475	471	474	01020000A034BF0D00020000000092B9B7F7D5E7BF80CB21856B3C13C000000000000008408034FF4EEED4E6BF301739B28C5C13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lP	0.512835680985825326	476	457	476	01020000A034BF0D000200000080F5B51E2CD5F0BFE088E89125971DC000000000000008408003FADFAE0FE6BFF04B3A66D0231CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.680433642555001938	477	452	477	01020000A034BF0D0002000000004C1A109A22E93F28897F828FFD20C00000000000000840004C1A109A22E93F8095376C5B421FC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lQ	2.47172150532520174	478	478	479	01020000A034BF0D00040000004069437C6A810CC060D06649BBDE2CC000000000000008404069437C6A810CC050F7975167FB2DC000000000000008404069437C6A810CC0309D3316886B2EC00000000000000840207863FE4CE802C0BCCCD5BAE76830C00000000000000840	\N	\N
second_floor	\N	0.257445718287996783	479	480	478	01020000A034BF0D00020000004069437C6A810CC0C8BA8D5CEB5A2CC000000000000008404069437C6A810CC060D06649BBDE2CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.91313261121472822	480	451	480	01020000A034BF0D000600000080DCB2204E8804C0F0C85F011B9E27C00000000000000840E05CDC2E214303C0D868D53D66EF27C00000000000000840E05CDC2E214303C0F0161D1FE10328C000000000000008404069437C6A810CC008DA767273532AC000000000000008404069437C6A810CC0D8935C543F3E2BC000000000000008404069437C6A810CC0C8BA8D5CEB5A2CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lQ	0.49045160207700178	481	479	481	01020000A034BF0D0002000000207863FE4CE802C0BCCCD5BAE76830C00000000000000840207863FE4CE802C0C4FD4CF775E630C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lQ	2.19819636366508453	482	481	482	01020000A034BF0D0003000000207863FE4CE802C0C4FD4CF775E630C00000000000000840800ABFD434D6ECBF747473F0CD5C32C00000000000000840802FA1F870ABE8BF747473F0CD5C32C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lQ	0.764264763208236775	483	481	483	01020000A034BF0D0003000000207863FE4CE802C0C4FD4CF775E630C0000000000000084040C6E66CB0FC02C088671D6502E930C0000000000000084040C6E66CB0FC02C0FC189D930EA931C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lQ	3.64489919105270133	484	483	484	01020000A034BF0D000200000040C6E66CB0FC02C0FC189D930EA931C0000000000000084040C6E66CB0FC02C0C4E2A3B0264E35C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lQ	0.174547963211470591	485	484	485	01020000A034BF0D000300000040C6E66CB0FC02C0C4E2A3B0264E35C00000000000000840E0DC705854D902C0EC9F3233925235C0000000000000084000CA6284DCA501C0EC9F3233925235C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lQ	0.287546116162318677	486	484	486	01020000A034BF0D000500000040C6E66CB0FC02C0C4E2A3B0264E35C00000000000000840C0BCDF82F46203C094016333EF5A35C00000000000000840C0BCDF82F46203C0508E7B114A5C35C00000000000000840E0BDD788106302C02C8EBC90467C35C00000000000000840E0BDD788106302C0AC98E401388535C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lD	1.79809885877850206	487	487	488	01020000A034BF0D00030000006050BBD74E5A12C0FC189D930EA931C00000000000000840409E1DE8A69314C0FC189D930EA931C00000000000000840400781AB8F8B19C0FC189D930EA931C00000000000000840	\N	\N
second_floor	\N	0.250000000000483169	488	489	487	01020000A034BF0D0002000000404EBBD74E5A11C0FC189D930EA931C000000000000008406050BBD74E5A12C0FC189D930EA931C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lQ	1.96480800630050112	489	483	489	01020000A034BF0D000300000040C6E66CB0FC02C0FC189D930EA931C00000000000000840C000B28EED410EC0FC189D930EA931C00000000000000840404EBBD74E5A11C0FC189D930EA931C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lD	1.92035734862469099	490	488	490	01020000A034BF0D0002000000400781AB8F8B19C0FC189D930EA931C00000000000000840400781AB8F8B19C0EC12A61DAB9433C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l7	1.27613336202120209	491	491	492	01020000A034BF0D0004000000F05DA33F68DE20C0A4D0749DE5AC35C0000000000000084050C2DE1EB8AB21C0A4D0749DE5AC35C0000000000000084030243411B0CE21C0A4D0749DE5AC35C00000000000000840308A991BCBF222C0A483A722F33E36C00000000000000840	\N	\N
second_floor	\N	0.249999999999488409	492	493	491	01020000A034BF0D0002000000105FA33F685E20C0A4D0749DE5AC35C00000000000000840F05DA33F68DE20C0A4D0749DE5AC35C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lD	3.67725346733186065	493	490	493	01020000A034BF0D0005000000400781AB8F8B19C0EC12A61DAB9433C00000000000000840400781AB8F8B19C0F0130479B94E35C0000000000000084010FA433D40041BC0A4D0749DE5AC35C0000000000000084050F5CFC030221FC0A4D0749DE5AC35C00000000000000840105FA33F685E20C0A4D0749DE5AC35C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l7	2.02896715623166379	494	492	494	01020000A034BF0D0006000000308A991BCBF222C0A483A722F33E36C0000000000000084028CE986A3C7223C0A483A722F33E36C00000000000000840488ADD50167623C0ACE1C915E04036C00000000000000840F097B627E37826C0ACE1C915E04036C00000000000000840F8CABD00F07D26C0244846A9593E36C00000000000000840F8CABD00F0FD26C0244846A9593E36C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l7	1.21357020913911451	495	492	495	01020000A034BF0D0002000000308A991BCBF222C0A483A722F33E36C0000000000000084078B7711D6F3B21C0FC6CBB21A11A37C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048l0	3.52797968789575611	496	496	497	01020000A034BF0D0007000000F05DA33F68DE20C0EC12A61DAB9433C0000000000000084050C2DE1EB8AB21C0EC12A61DAB9433C00000000000000840F8B832025EC721C0EC12A61DAB9433C000000000000008409051437018B822C0385FAE54080D34C00000000000000840E08CC814B4EA26C0385FAE54080D34C0000000000000084018418B45642427C054B90F6DE02934C00000000000000840D84014EA1F7127C054B90F6DE02934C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lD	1.79809885877850206	498	490	498	01020000A034BF0D0003000000400781AB8F8B19C0EC12A61DAB9433C0000000000000084050F5CFC030221FC0EC12A61DAB9433C00000000000000840105FA33F685E20C0EC12A61DAB9433C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.32877713142249831	499	499	450	01020000A034BF0D000300000070B4213EB5C014C0B00C467B70462CC0000000000000084070B4213EB5C014C0C0E51473C4292BC0000000000000084070B4213EB5C014C0F0C85F011B9E27C00000000000000840	\N	\N
second_floor	\N	0.0928257648554620118	500	500	499	01020000A034BF0D000200000070B4213EB5C014C0409C1657F7752CC0000000000000084070B4213EB5C014C0B00C467B70462CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lD	3.92624478699333679	501	488	500	01020000A034BF0D0005000000400781AB8F8B19C0FC189D930EA931C00000000000000840400781AB8F8B19C0D8BB7CE04B0730C0000000000000084070B4213EB5C014C048CE498A2AA92DC0000000000000084070B4213EB5C014C030C3475FA3922DC0000000000000084070B4213EB5C014C0409C1657F7752CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lQ	2.16480328800760979	502	479	501	01020000A034BF0D0005000000207863FE4CE802C0BCCCD5BAE76830C000000000000008400001287750F0FFBFCCDD7B22E30A30C0000000000000084040D91CD0328AFDBFCCDD7B22E30A30C0000000000000084000A6F784CA9EF4BFFC302EA7999930C00000000000000840004CEF09953DE9BFFC302EA7991931C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	10.1474003306424478	503	449	502	01020000A034BF0D000300000060347A8B256C17C0F0C85F011B9E27C00000000000000840301A9ED3BD9619C008D64DDDCE8826C00000000000000840301A9ED3BD9619C0407B8399F92BFEBF0000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.0403556115579419838	504	502	503	01020000A034BF0D0002000000301A9ED3BD9619C0407B8399F92BFEBF0000000000000840301A9ED3BD9619C0C0DB85ACAD86FDBF0000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.0774638183925731028	505	503	504	01020000A034BF0D0002000000301A9ED3BD9619C0C0DB85ACAD86FDBF0000000000000840301A9ED3BD9619C0C0F21BF96249FCBF0000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048ie	3.28566286245995709	506	505	506	01020000A034BF0D00050000006079F527AB7011C0C0DB85ACAD86FDBF00000000000008404061FDD216AC0FC0C0DB85ACAD86FDBF0000000000000840A01447DF18D70EC0C0DB85ACAD86FDBF0000000000000840808F772C8C7A0AC080D1E64694CDF4BF000000000000084000C3E64694CDF4BF80D1E64694CDF4BF0000000000000840	\N	\N
second_floor	\N	0.249999999999801048	507	507	505	01020000A034BF0D00020000008078F527AB7012C0C0DB85ACAD86FDBF00000000000008406079F527AB7011C0C0DB85ACAD86FDBF0000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.78718059746499591	508	503	507	01020000A034BF0D0003000000301A9ED3BD9619C0C0DB85ACAD86FDBF000000000000084030416CE64A0B14C0C0DB85ACAD86FDBF00000000000008408078F527AB7012C0C0DB85ACAD86FDBF0000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048il	3.35773400212494488	509	508	509	01020000A034BF0D0007000000F05DA33F68DE20C0407B8399F92BFEBF000000000000084050C2DE1EB8AB21C0407B8399F92BFEBF0000000000000840B0A684BA7CCC21C0407B8399F92BFEBF000000000000084048A3049220FD22C0C09683DDDAA6F4BF000000000000084090438D362AB326C0C09683DDDAA6F4BF0000000000000840509860EFAACC26C080F0E816D5DAF3BF00000000000008401079B440D10C27C080F0E816D5DAF3BF0000000000000840	\N	\N
second_floor	\N	0.25	510	510	508	01020000A034BF0D0002000000F05DA33F685E20C0407B8399F92BFEBF0000000000000840F05DA33F68DE20C0407B8399F92BFEBF0000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.78718059746499591	511	502	510	01020000A034BF0D0003000000301A9ED3BD9619C0407B8399F92BFEBF000000000000084010F3CFC030221FC0407B8399F92BFEBF0000000000000840F05DA33F685E20C0407B8399F92BFEBF0000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.760524743047258811	512	447	511	01020000A034BF0D0003000000F8788019788324C0D8EDB5F420A327C0000000000000084050A4B0C2940825C03019E69D3D2828C0000000000000084050A4B0C2940825C0909B9E7061F128C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.65972356744519622	513	446	512	01020000A034BF0D000500000070E5CB16888E29C0A0C8AB774CA125C0000000000000084020389449CFE02AC0F075E344054F24C0000000000000084020389449CFE02AC07863B274DEBE21C00000000000000840F00461169C2D2BC0A896E5A7117221C00000000000000840F00461169C2D2BC010E0328373FB20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.68677859038749034	514	512	513	01020000A034BF0D0002000000F00461169C2D2BC010E0328373FB20C00000000000000840F00461169C2D2BC080856023A4371FC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.33441322148874097	515	514	515	01020000A034BF0D00030000001865BD4E9F1129C010E0328373FB20C000000000000008409882DED5B52A28C010E0328373FB20C00000000000000840D84F6758E4EA26C0500EA35738771FC00000000000000840	\N	\N
second_floor	\N	0.249970558235915519	516	516	514	01020000A034BF0D00020000003091D6729B9129C010E0328373FB20C000000000000008401865BD4E9F1129C010E0328373FB20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.804692373896500612	517	512	516	01020000A034BF0D0003000000F00461169C2D2BC010E0328373FB20C00000000000000840288FABEB84782AC010E0328373FB20C000000000000008403091D6729B9129C010E0328373FB20C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.84658593531987258	518	515	517	01020000A034BF0D0004000000D84F6758E4EA26C0500EA35738771FC0000000000000084048145ABFDAEA26C0500EA35738771FC000000000000008408069BC8F9B9126C0F8316F5BDB1420C00000000000000840A85F773F685E23C0F8316F5BDB1420C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	0.729643968321006531	519	515	518	01020000A034BF0D0003000000D84F6758E4EA26C0500EA35738771FC000000000000008409855AADD187827C0A04CBA77D45C1EC00000000000000840C81ADF741A7827C060D6707B0C011DC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.00397283970075257	520	518	519	01020000A034BF0D0003000000C81ADF741A7827C060D6707B0C011DC00000000000000840C00D375098E327C0103C93B3142A1CC000000000000008401084D38C95E328C040325D3A1A2A1AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.63891211182687013	521	518	520	01020000A034BF0D0004000000C81ADF741A7827C060D6707B0C011DC00000000000000840E0FCB6D1F14427C0809A2035BB9A1CC00000000000000840E0FCB6D1F14427C0203070B2579A17C0000000000000084028A17C8670EB26C0B078FB1B55E716C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	0.429973598563549331	522	520	521	01020000A034BF0D000200000028A17C8670EB26C0B078FB1B55E716C0000000000000084088AE9C064B0F26C0B078FB1B55E716C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.04999999600188687	523	521	522	01020000A034BF0D000300000088AE9C064B0F26C0B078FB1B55E716C0000000000000084050773460860225C0B078FB1B55E716C00000000000000840E06C256DB1F523C0B078FB1B55E716C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048ia	0.944950908845351822	524	523	524	01020000A034BF0D0005000000E06C256DB1F523C0F0F826E7590B13C00000000000000840E06C256DB1F523C03030B028BA7011C00000000000000840E06C256DB1F523C0502EEA7BC41F11C00000000000000840C06C256DB1F523C0102EEA7BC41F11C00000000000000840C06C256DB1F523C0606A3F6271870EC00000000000000840	\N	\N
second_floor	\N	0.0899999999996197175	525	525	523	01020000A034BF0D0002000000E06C256DB1F523C0A086E9DC826713C00000000000000840E06C256DB1F523C0F0F826E7590B13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	0.874825463743505338	526	522	525	01020000A034BF0D0003000000E06C256DB1F523C0B078FB1B55E716C00000000000000840E06C256DB1F523C0604F609B220215C00000000000000840E06C256DB1F523C0A086E9DC826713C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iX	0.953872625850570866	527	526	527	01020000A034BF0D000500000088E0DC5CA2C321C0F0F826E7590B13C0000000000000084088E0DC5CA2C321C03030B028BA7011C0000000000000084088E0DC5CA2C321C060F6B3ACE54011C000000000000008406090243E1DD821C0B09624EAEF1711C000000000000008406090243E1DD821C02099CA851A970EC00000000000000840	\N	\N
second_floor	\N	0.0899999999996197175	528	528	526	01020000A034BF0D000200000088E0DC5CA2C321C0A086E9DC826713C0000000000000084088E0DC5CA2C321C0F0F826E7590B13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.72239760869136704	529	522	528	01020000A034BF0D0006000000E06C256DB1F523C0B078FB1B55E716C000000000000008406064167ADCE822C0B078FB1B55E716C00000000000000840F8562C5F519E22C0B078FB1B55E716C0000000000000084088E0DC5CA2C321C0D08B5C17F73115C0000000000000084088E0DC5CA2C321C0604F609B220215C0000000000000084088E0DC5CA2C321C0A086E9DC826713C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048ix	0.945075263554304601	530	529	530	01020000A034BF0D000500000088AE9C064B0F26C0F0F826E7590B13C0000000000000084088AE9C064B0F26C03030B028BA7011C0000000000000084088AE9C064B0F26C020D03715E51F11C00000000000000840A0AE9C064B0F26C0F0CF3715E51F11C00000000000000840A0AE9C064B0F26C0A026A42F30870EC00000000000000840	\N	\N
second_floor	\N	0.0899999999996197175	531	531	529	01020000A034BF0D000200000088AE9C064B0F26C0A086E9DC826713C0000000000000084088AE9C064B0F26C0F0F826E7590B13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	0.874825463743505338	532	521	531	01020000A034BF0D000300000088AE9C064B0F26C0B078FB1B55E716C0000000000000084088AE9C064B0F26C0604F609B220215C0000000000000084088AE9C064B0F26C0A086E9DC826713C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048i_	0.0226459209316883375	533	532	533	01020000A034BF0D0002000000307CAFA8562828C050F726E7590B13C0000000000000084078DEA186893028C0C032422BF4FA12C00000000000000840	\N	\N
second_floor	\N	0.116738465468237254	534	534	532	01020000A034BF0D0003000000280AB6A6490728C0A086E9DC826713C00000000000000840280AB6A6490728C070DB19EB734D13C00000000000000840307CAFA8562828C050F726E7590B13C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.10446169916671755	535	520	534	01020000A034BF0D000400000028A17C8670EB26C0B078FB1B55E716C0000000000000084030E804AD0F1C27C0A0EAEACE168616C00000000000000840280AB6A6490728C0B0A688DBA2AF14C00000000000000840280AB6A6490728C0A086E9DC826713C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048i_	1.04118803574269925	536	533	535	01020000A034BF0D000700000078DEA186893028C0C032422BF4FA12C0000000000000084078DEA186893028C0902EB028BA7011C0000000000000084078DEA186893028C000E1E53F5B4811C00000000000000840D0FA5B62912228C0B0195AF76A2C11C00000000000000840D0FA5B62912228C0E02249BDDC8C0EC00000000000000840700AB2397E0228C06061A11A900C0EC00000000000000840700AB2397E0228C0A0D1B7C8D7ED0DC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048iY	0.24801179887113603	537	536	537	01020000A034BF0D0003000000688875DFD06628C0A086E9DC826713C00000000000000840A065A92255B228C0104151638BFE13C00000000000000840688C0E9784C628C0104151638BFE13C00000000000000840	\N	\N
second_floor	\N	0.127279220613563282	538	538	536	01020000A034BF0D0002000000C0409464BC3828C050F726E7590B13C00000000000000840688875DFD06628C0A086E9DC826713C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048i_	0.0226459209316883375	539	533	538	01020000A034BF0D000200000078DEA186893028C0C032422BF4FA12C00000000000000840C0409464BC3828C050F726E7590B13C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Mn	3.95391621922730296	540	539	540	01020000A034BF0D000B00000024B4F1A7B3A030C058FCC28A664523C0000000000000084024B4F1A7B3A030C080F72720617622C000000000000008404C0E56E392A030C0D8ABF0961F7622C000000000000008404C0E56E392A030C01821C90BFC2822C000000000000008405CA3AC8A093630C0304B765AE95321C000000000000008405CA3AC8A093630C0908D8457D85620C000000000000008407000FB90840330C0708F42C89CE31FC000000000000008407000FB90840330C0E0D47EF7372A1CC000000000000008407000FB90840330C070C8F88AEC7018C000000000000008408C8EDE26AF0F30C000906A33424018C000000000000008408C8EDE26AF0F30C0B048466494D217C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	541	541	539	01020000A034BF0D000200000024B4F1A7B3A030C0A03A7185218023C0000000000000084024B4F1A7B3A030C058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144698998	542	445	541	01020000A034BF0D000300000024B4F1A7B3A030C058D009A2F9CC25C0000000000000084024B4F1A7B3A030C09061A28DCD9C24C0000000000000084024B4F1A7B3A030C0A03A7185218023C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Mo	3.9177370883842153	543	542	543	01020000A034BF0D0006000000302A3BB525F332C058FCC28A664523C00000000000000840302A3BB525F332C080F72720617622C0000000000000084010849FF004F332C040ABF0961F7622C0000000000000084010849FF004F332C0A821C90BFC2822C0000000000000084098083048866332C0B82AEABAFE0921C0000000000000084098083048866332C06036261400CD17C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	544	544	542	01020000A034BF0D0002000000302A3BB525F332C0A03A7185218023C00000000000000840302A3BB525F332C058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144698998	545	444	544	01020000A034BF0D0003000000302A3BB525F332C058D009A2F9CC25C00000000000000840302A3BB525F332C09061A28DCD9C24C00000000000000840302A3BB525F332C0A03A7185218023C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Mo	0.794829018554867983	546	543	545	01020000A034BF0D000300000098083048866332C06036261400CD17C00000000000000840885684B57FF232C0A0FED45E1A9115C00000000000000840885684B57FF232C0B06683A6FB8B15C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Mo	0.111689468351547194	547	543	546	01020000A034BF0D000200000098083048866332C06036261400CD17C00000000000000840D0CE647C4E4F32C0404FF9E4207C17C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.16324328044452718	548	439	547	01020000A034BF0D00040000001478CFF27D8134C038747ADF03A427C00000000000000840DC63433B30FD32C0A89C924E9FAC2AC00000000000000840DC63433B30FD32C098166E11F1B32AC00000000000000840F458A3AC7DFC32C0682CAE2E56B52AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MC	1.69813226291298269	549	548	549	01020000A034BF0D0004000000686D51F45E5732C0682CAE2E56B52AC00000000000000840F0D938F008C931C0682CAE2E56B52AC000000000000008401CB5326F732531C0682CAE2E56B52AC00000000000000840C4AFACCE5FCA30C01837BA6F7D6B2BC00000000000000840	\N	\N
second_floor	\N	0.0944491311510091691	550	550	548	01020000A034BF0D000200000048DBCAC58C6F32C0682CAE2E56B52AC00000000000000840686D51F45E5732C0682CAE2E56B52AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.550550868849015274	551	547	550	01020000A034BF0D0002000000F458A3AC7DFC32C0682CAE2E56B52AC0000000000000084048DBCAC58C6F32C0682CAE2E56B52AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MC	3.54203926811741532	552	549	551	01020000A034BF0D0007000000C4AFACCE5FCA30C01837BA6F7D6B2BC00000000000000840C4AFACCE5FCA30C0C8F3256190EA2BC00000000000000840C4AFACCE5FCA30C0B87BFA75BE1530C00000000000000840184A7CB3739830C064E12A91AA4730C00000000000000840184A7CB3739830C0D4E153D3DAFE30C0000000000000084000A8FA86D2A330C0BC3FD2A6390A31C0000000000000084000A8FA86D2A330C0C4DA1D681E2731C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MC	1.32802359982341156	553	549	552	01020000A034BF0D0003000000C4AFACCE5FCA30C01837BA6F7D6B2BC0000000000000084068D549BB932030C06082F448E5172AC000000000000008402014D20977792FC06082F448E5172AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MB	3.65988953173157849	554	553	554	01020000A034BF0D000A000000F458A3AC7DFC32C0608DBFFA29042CC00000000000000840F458A3AC7DFC32C058925A652FD32CC00000000000000840D4FE3E719EFC32C018DE91EE70D32CC00000000000000840D4FE3E719EFC32C08868B97994202DC00000000000000840D0410410800F34C080EE43B757462FC00000000000000840D0410410800F34C0A4EE972ED62930C00000000000000840208CD6DFB02F34C0F4386AFE064A30C00000000000000840208CD6DFB02F34C090437A93A7FC30C0000000000000084088D2DABDB12234C028FD75B5A60931C0000000000000084088D2DABDB12234C0E4DE5B49622631C00000000000000840	\N	\N
second_floor	\N	0.117704428251997228	555	555	553	01020000A034BF0D0002000000F458A3AC7DFC32C0C8AD8339E6C72BC00000000000000840F458A3AC7DFC32C0608DBFFA29042CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.536255205691020365	556	547	555	01020000A034BF0D0002000000F458A3AC7DFC32C0682CAE2E56B52AC00000000000000840F458A3AC7DFC32C0C8AD8339E6C72BC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6M6	3.67388455316772999	557	556	557	01020000A034BF0D000A000000FC6B4EE547FD38C0608DBFFA29042CC00000000000000840FC6B4EE547FD38C058925A652FD32CC000000000000008400CC6B22027FD38C038DE91EE70D32CC000000000000008400CC6B22027FD38C06868B97994202DC00000000000000840C4DF0774C6EA37C0F8340FD355452FC00000000000000840C4DF0774C6EA37C0E0917D3C552930C0000000000000084034AFC595AFC937C070C2BF1A6C4A30C0000000000000084034AFC595AFC937C014BA247742FC30C00000000000000840180A78BB91D737C0F814D79C240A31C00000000000000840180A78BB91D737C0B0C2E58C6F2931C00000000000000840	\N	\N
second_floor	\N	0.117704428251997228	558	558	556	01020000A034BF0D0002000000FC6B4EE547FD38C0C8AD8339E6C72BC00000000000000840FC6B4EE547FD38C0608DBFFA29042CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.07008630144699168	559	434	558	01020000A034BF0D0003000000FC6B4EE547FD38C038747ADF03A427C00000000000000840FC6B4EE547FD38C0D88652313AAB2AC00000000000000840FC6B4EE547FD38C0C8AD8339E6C72BC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6M5	3.67268547063345041	560	559	560	01020000A034BF0D000A000000309F81187B303AC0608DBFFA29042CC00000000000000840309F81187B303AC050925A652FD32CC0000000000000084004451DDD9B303AC0F8DD91EE70D32CC0000000000000084004451DDD9B303AC0A868B97994202DC000000000000008402C2BC889FC423BC0F8340FD355452FC000000000000008402C2BC889FC423BC0AC8F3A933E2130C000000000000008409C68D260A0633BC01CCD446AE24130C000000000000008409C68D260A0633BC04407D6ABDEFC30C000000000000008400C429E7125563BC0D42D0A9B590A31C000000000000008400C429E7125563BC07C819F5D7B2931C00000000000000840	\N	\N
second_floor	\N	0.117704428251997228	561	561	559	01020000A034BF0D0002000000309F81187B303AC0C8AD8339E6C72BC00000000000000840309F81187B303AC0608DBFFA29042CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.07008630144699168	562	429	561	01020000A034BF0D0003000000309F81187B303AC038747ADF03A427C00000000000000840309F81187B303AC0D88652313AAB2AC00000000000000840309F81187B303AC0C8AD8339E6C72BC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6M0	5.76126341087317506	563	562	563	01020000A034BF0D000B0000004856D4771B3C3DC0D842A7C82A9F2AC00000000000000840C0E9EC7B71CA3DC0D842A7C82A9F2AC0000000000000084020D7F92095D33DC0D842A7C82A9F2AC0000000000000084074B87435431B3EC02880B19FCE0F2AC00000000000000840BCFA29CD535C3EC02880B19FCE0F2AC0000000000000084064C9F15F461D3FC0781D41C5B3912BC0000000000000084064C9F15F461D3FC0B4EC7AF7C22030C00000000000000840F48BE788A2FC3EC0242A85CE664130C00000000000000840F48BE788A2FC3EC03CAA95475AFD30C00000000000000840DC7961E1080A3FC024980FA0C00A31C00000000000000840DC7961E1080A3FC0CCEBA462E22931C00000000000000840	\N	\N
second_floor	\N	0.0990523598810000294	564	564	562	01020000A034BF0D0002000000780EFEF8BF223DC0D842A7C82A9F2AC000000000000008404856D4771B3C3DC0D842A7C82A9F2AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.68748455667194364	565	428	564	01020000A034BF0D0004000000AC71F9CBCE103BC038747ADF03A427C0000000000000084000D98F40628E3CC0D842A7C82A9F2AC00000000000000840007BE5F469943CC0D842A7C82A9F2AC00000000000000840780EFEF8BF223DC0D842A7C82A9F2AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6M_	3.95726694323858164	566	565	566	01020000A034BF0D000A000000F45BF6C287593BC058FCC28A664523C00000000000000840F45BF6C287593BC068F72720617622C0000000000000084094019287A8593BC028ACF0961F7622C0000000000000084094019287A8593BC0A820C90BFC2822C00000000000000840B45C0C5092D73BC0606AD47A282D21C00000000000000840B45C0C5092D73BC0D8253B53C13020C00000000000000840249A162736F83BC0F0554D4AF3DE1FC00000000000000840249A162736F83BC0B0D96A2B337818C0000000000000084094A7D685D1EA3BC0700F6BA6A04218C0000000000000084094A7D685D1EA3BC090E27A6BA9D317C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	567	567	565	01020000A034BF0D0002000000F45BF6C287593BC0A03A7185218023C00000000000000840F45BF6C287593BC058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.78601396263049139	568	427	567	01020000A034BF0D0003000000F45BF6C287593BC0A89F80F1911227C00000000000000840F45BF6C287593BC09061A28DCD9C24C00000000000000840F45BF6C287593BC0A03A7185218023C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MV	1.99243655854302282	569	568	569	01020000A034BF0D0004000000A28CEF4DD9CA40C0D0BB70247F5128C00000000000000840A28CEF4DD9CA40C0C0E2A12C2B6E29C00000000000000840A28CEF4DD9CA40C038B299800ED429C00000000000000840720A1B4CD93A41C078A947790E942BC00000000000000840	\N	\N
second_floor	\N	0.108744794309004078	570	570	568	01020000A034BF0D0002000000A28CEF4DD9CA40C01866A2BED11928C00000000000000840A28CEF4DD9CA40C0D0BB70247F5128C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144700419	571	422	570	01020000A034BF0D0003000000A28CEF4DD9CA40C058D009A2F9CC25C00000000000000840A28CEF4DD9CA40C0283F71B625FD26C00000000000000840A28CEF4DD9CA40C01866A2BED11928C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MV	3.4454310311275278	572	569	571	01020000A034BF0D0006000000720A1B4CD93A41C078A947790E942BC00000000000000840720A1B4CD93A41C0509291EF562C30C000000000000008402A29A0372B4B41C0C0CF9BC6FA4C30C000000000000008402A29A0372B4B41C0E8ED011B56FC30C00000000000000840E8F91B995E4441C06C4C0A58EF0931C00000000000000840E8F91B995E4441C0D81530EDE72831C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MQ	5.66938160823340276	573	572	573	01020000A034BF0D000B000000A46DE562C63742C02893DB4C143F2AC0000000000000084060B7F164F17E42C02893DB4C143F2AC00000000000000840CCC97425BCA042C02893DB4C143F2AC00000000000000840A2763AE9F3A942C0C8DFC43D351A2AC00000000000000840A69B727477CA42C0C8DFC43D351A2AC0000000000000084096BD8BFFAB2843C08867296A07932BC0000000000000084096BD8BFFAB2843C058710268D32B30C00000000000000840DE9E06145A1843C0C8AE0C3F774C30C00000000000000840DE9E06145A1843C0E00E91A2D9FC30C00000000000000840DA795919FE1E43C0D8C436AD210A31C00000000000000840DA795919FE1E43C0D0F470F0612A31C00000000000000840	\N	\N
second_floor	\N	0.0900000000000034106	574	574	572	01020000A034BF0D0002000000B81B2D44412C42C02893DB4C143F2AC00000000000000840A46DE562C63742C02893DB4C143F2AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MV	2.22149827801891142	575	569	574	01020000A034BF0D0006000000720A1B4CD93A41C078A947790E942BC00000000000000840DEBCFB9A4F9941C0C8DFC43D351A2AC00000000000000840BA12D8BD13BA41C0C8DFC43D351A2AC0000000000000084090BF9D814BC341C02893DB4C143F2AC00000000000000840FCD1204216E541C02893DB4C143F2AC00000000000000840B81B2D44412C42C02893DB4C143F2AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MP	5.74862458177883262	576	575	576	01020000A034BF0D000B00000050B5C6DDDAC545C01097699D8F9B2AC00000000000000840966BBADBAF7E45C01097699D8F9B2AC00000000000000840EEFCA758EF7345C01097699D8F9B2AC00000000000000840B63D180CA35345C0389A2A6B5E1A2AC0000000000000084012E30B9CC43245C0389A2A6B5E1A2AC000000000000008408E4AB6CEC7D444C048FC80A051922BC000000000000008408E4AB6CEC7D444C020F693B0A12B30C0000000000000084046693BBA19E544C090339E87454C30C0000000000000084046693BBA19E544C030CED4B45DFD30C000000000000008402AE29E425CDE44C068DC0DA4D80A31C000000000000008402AE29E425CDE44C0B082D8B9EF2A31C00000000000000840	\N	\N
second_floor	\N	0.0900000000000034106	577	577	575	01020000A034BF0D00020000003C077FFC5FD145C01097699D8F9B2AC0000000000000084050B5C6DDDAC545C01097699D8F9B2AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.70214075262370335	578	405	577	01020000A034BF0D000400000046C63E9D2FDE46C0C836700860B327C00000000000000840326E00B8232446C01097699D8F9B2AC00000000000000840F6508BFE8A1846C01097699D8F9B2AC000000000000008403C077FFC5FD145C01097699D8F9B2AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MK	3.64089571896671815	579	578	579	01020000A034BF0D000A000000EADD226D9D4B47C0C8AB17E570162CC00000000000000840EADD226D9D4B47C0D0B0B24F76E52CC00000000000000840220BD50A8D4B47C0E8FBE9D8B7E52CC00000000000000840220BD50A8D4B47C0A0871164DB322DC00000000000000840CA548D7238C246C0086130C52D582FC00000000000000840CA548D7238C246C0843098E2162C30C0000000000000084012360887E6B146C0F46DA2B9BA4C30C0000000000000084012360887E6B146C0CC93D082E8FC30C0000000000000084032B942B399B846C00C9A45DB4E0A31C0000000000000084032B942B399B846C0544010F1652A31C00000000000000840	\N	\N
second_floor	\N	0.0934017198709966578	580	580	578	01020000A034BF0D0002000000EADD226D9D4B47C0E8326F8B9EE62BC00000000000000840EADD226D9D4B47C0C8AB17E570162CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.10008630144699282	581	404	580	01020000A034BF0D0003000000EADD226D9D4B47C0C836700860B327C00000000000000840EADD226D9D4B47C0F80B3E83F2C92AC00000000000000840EADD226D9D4B47C0E8326F8B9EE62BC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6MJ	3.64240924473739858	582	581	582	01020000A034BF0D000A0000008277BC0637E547C0C8AB17E570162CC000000000000008408277BC0637E547C0C8B0B24F76E52CC00000000000000840A24A0A6947E547C050FDE9D8B7E52CC00000000000000840A24A0A6947E547C030861164DB322DC00000000000000840F6FDCC43626E48C078531CCF46572FC00000000000000840F6FDCC43626E48C01C8D9326C92B30C00000000000000840AE1C522FB47E48C08CCA9DFD6C4C30C00000000000000840AE1C522FB47E48C044244A2B85FD30C00000000000000840B60B1BDCF57748C03446B8D1010B31C00000000000000840B60B1BDCF57748C0CC6213BAEF2A31C00000000000000840	\N	\N
second_floor	\N	0.0934017198709966578	583	583	581	01020000A034BF0D00020000008277BC0637E547C0E8326F8B9EE62BC000000000000008408277BC0637E547C0C8AB17E570162CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.10008630144699282	584	399	583	01020000A034BF0D00030000008277BC0637E547C0C836700860B327C000000000000008408277BC0637E547C0F80B3E83F2C92AC000000000000008408277BC0637E547C0E8326F8B9EE62BC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6LL	3.96223703471859023	585	584	585	01020000A034BF0D000A000000FA74D8DA927948C058FCC28A664523C00000000000000840FA74D8DA927948C058F72720617622C00000000000000840EA47263DA37948C090ABF0961F7622C00000000000000840EA47263DA37948C03021C90BFC2822C00000000000000840C6E8C20A97B848C0C89D56D52C2D21C00000000000000840C6E8C20A97B848C0B84686E1B53120C00000000000000840820748F6E8C848C09097E366DCE01FC00000000000000840820748F6E8C848C030D088741F7A18C00000000000000840FE5F79CA37C248C010941316964418C00000000000000840FE5F79CA37C248C01072AF248BCE17C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	586	586	584	01020000A034BF0D0002000000FA74D8DA927948C0A03A7185218023C00000000000000840FA74D8DA927948C058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.10008630144700703	587	398	586	01020000A034BF0D0003000000FA74D8DA927948C0C836700860B327C00000000000000840FA74D8DA927948C09061A28DCD9C24C00000000000000840FA74D8DA927948C0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.09845406209645358	588	397	587	01020000A034BF0D00020000006AA776C5A31E4AC0C836700860B327C000000000000008402A89E0F291DC4AC0D0BD17BE18AB2AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Nk	0.431801161535688593	589	588	589	01020000A034BF0D00030000001A4A73B5BFE44AC0C8AB17E570162CC000000000000008401A4A73B5BFE44AC0101D24A83FF12CC00000000000000840BEA46EA426E54AC0A0871164DBF22CC00000000000000840	\N	\N
second_floor	\N	0.0934017198709966578	590	590	588	01020000A034BF0D00020000001A4A73B5BFE44AC0E8326F8B9EE62BC000000000000008401A4A73B5BFE44AC0C8AB17E570162CC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.642721995200796981	591	587	590	01020000A034BF0D00030000002A89E0F291DC4AC0D0BD17BE18AB2AC000000000000008401A4A73B5BFE44AC088C162C8CFCB2AC000000000000008401A4A73B5BFE44AC0E8326F8B9EE62BC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Nk	3.21016691692983347	592	589	591	01020000A034BF0D0008000000BEA46EA426E54AC0A0871164DBF22CC00000000000000840BEA46EA426E54AC0B8871164DB322DC000000000000008403208A4E7D25B4AC0E8F93B572A582FC000000000000008403208A4E7D25B4AC05460A3EA3A2C30C000000000000008407AE91EFC804B4AC0C49DADC1DE4C30C000000000000008407AE91EFC804B4AC00C513A6713FD30C00000000000000840C2E2BE4C33524AC09C437A08780A31C00000000000000840C2E2BE4C33524AC03460D5F0652A31C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Nk	0.0191456334580311534	593	589	592	01020000A034BF0D0003000000BEA46EA426E54AC0A0871164DBF22CC000000000000008403A96D315CBE64AC0B8C17D9E49EC2CC00000000000000840BA3B6FDAEBE64AC0B8C17D9E49EC2CC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Ng	1.71837064130224659	594	593	594	01020000A034BF0D0004000000A26DE562C6374BC0D0BD17BE18AB2AC000000000000008405AB7F164F17E4BC0D0BD17BE18AB2AC000000000000008407A8B80D1D8CA4BC0D0BD17BE18AB2AC00000000000000840762D136861FE4BC0C84562183B792BC00000000000000840	\N	\N
second_floor	\N	0.0962825636510160621	595	595	593	01020000A034BF0D000200000072663666732B4BC0D0BD17BE18AB2AC00000000000000840A26DE562C6374BC0D0BD17BE18AB2AC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.61625520413014101	596	587	595	01020000A034BF0D00030000002A89E0F291DC4AC0D0BD17BE18AB2AC00000000000000840BA1C2A6448E44AC0D0BD17BE18AB2AC0000000000000084072663666732B4BC0D0BD17BE18AB2AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Ng	3.51831646826663524	597	594	596	01020000A034BF0D0007000000762D136861FE4BC0C84562183B792BC00000000000000840762D136861FE4BC030127E4BD7FC2BC00000000000000840762D136861FE4BC0F8CB9704C01830C000000000000008400AA44F8178154CC020B91037EE4630C000000000000008400AA44F8178154CC034BCE4E7580331C000000000000008405AFB95758F114CC0940D58FF2A0B31C000000000000008405AFB95758F114CC0B4B650BAEF2A31C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6Ng	1.25591647231050341	598	594	597	01020000A034BF0D0003000000762D136861FE4BC0C84562183B792BC000000000000008406AA98D355A544CC0F05578E257212AC00000000000000840AA55D6EE867B4CC0F05578E257212AC00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6LM	3.9843687642332446	599	598	599	01020000A034BF0D00090000002230B0040C4E4AC058FCC28A664523C000000000000008402230B0040C4E4AC068D59182BA2822C000000000000008402230B0040C4E4AC018955C24001F22C00000000000000840964B9AF18B114AC0E80205D8FF2C21C00000000000000840964B9AF18B114AC0D8AB34E4883120C00000000000000840DE2C15063A014AC0F061406C82E01FC00000000000000840DE2C15063A014AC0D0052C6F797A18C000000000000008409A8F1D7EF9074AC0F0EFE8AE7D4418C000000000000008409A8F1D7EF9074AC0303E9B6BBAAF17C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	600	600	598	01020000A034BF0D00020000002230B0040C4E4AC0A03A7185218023C000000000000008402230B0040C4E4AC058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.72971743634536779	601	396	600	01020000A034BF0D00030000002230B0040C4E4AC0E0138A0BBFF526C000000000000008402230B0040C4E4AC09061A28DCD9C24C000000000000008402230B0040C4E4AC0A03A7185218023C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6LR	3.95334153263834187	602	601	602	01020000A034BF0D000600000076BF72FA34EA4AC030FCC28A664523C0000000000000084076BF72FA34EA4AC050F72720617622C000000000000008408292C05C45EA4AC020ABF0961F7622C000000000000008408292C05C45EA4AC07021C90BFC2822C000000000000008401EEC2CE1E2314BC000BB17FA850A21C000000000000008401EEC2CE1E2314BC020EE8F8B1AA817C00000000000000840	\N	\N
second_floor	\N	0.114707788248068709	603	603	601	01020000A034BF0D000200000076BF72FA34EA4AC0A03A7185218023C0000000000000084076BF72FA34EA4AC030FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.17008630144700021	604	395	603	01020000A034BF0D000300000076BF72FA34EA4AC068A7AD1237D725C0000000000000084076BF72FA34EA4AC09061A28DCD9C24C0000000000000084076BF72FA34EA4AC0A03A7185218023C00000000000000840	\N	\N
second_floor	1BUg4a4jr0B9Q5NnDgB6LS	3.9861568793049007	605	604	605	01020000A034BF0D000B000000F6B180612A134CC058FCC28A664523C00000000000000840F6B180612A134CC050F72720617622C00000000000000840FE84CEC33A134CC030ABF0961F7622C00000000000000840FE84CEC33A134CC08821C90BFC2822C00000000000000840AAF902A295484CC0D84EF792905321C00000000000000840AAF902A295484CC018FCB31F715820C0000000000000084036DD9DC291614CC0D0DB903A01E91FC0000000000000084036DD9DC291614CC00015E8FE66611AC0000000000000084036DD9DC291614CC0D0C63FE94A7318C0000000000000084082157E5AD05B4CC0308941A83F4518C0000000000000084082157E5AD05B4CC030A5A91DDBAF17C00000000000000840	\N	\N
second_floor	\N	0.114707788247997655	606	606	604	01020000A034BF0D0002000000F6B180612A134CC0A03A7185218023C00000000000000840F6B180612A134CC058FCC28A664523C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.17008630144700021	607	394	606	01020000A034BF0D0003000000F6B180612A134CC068A7AD1237D725C00000000000000840F6B180612A134CC09061A28DCD9C24C00000000000000840F6B180612A134CC0A03A7185218023C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lE	1.03168724842709159	608	314	607	01020000A034BF0D0003000000D24212692D984DC0880F09DE84662AC0000000000000084012BF4DABE0564DC08800F7E6516129C00000000000000840729D11BACC3A4DC0087A062202F128C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lE	2.45202655902118671	609	313	608	01020000A034BF0D0006000000D24212692D984DC070E450AF8FAB2AC000000000000008408E0842B888974DC080CD917222AE2AC000000000000008408E0842B888974DC0686545C1E0E32BC000000000000008408E0842B888974DC0B8169694658F2CC000000000000008408E0842B888974DC0A09878F413172DC000000000000008408E0842B888974DC078166ED7EE912FC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lE	0.700130196159255425	610	608	609	01020000A034BF0D00020000008E0842B888974DC078166ED7EE912FC000000000000008400A67A82029584DC0B0DD0EA2B14730C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ048lE	0.749438712518126215	611	608	610	01020000A034BF0D00020000008E0842B888974DC078166ED7EE912FC0000000000000084022E5763D5CDB4DC0FC31A1C8A35030C00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.71181754123300323	612	611	448	01020000A034BF0D0002000000005EA33F689E22C0108FFE4D940F2DC00000000000000840005EA33F689E22C0D8EDB5F420A327C00000000000000840	\N	\N
second_floor	\N	3.88723068316779363	613	612	611	01020000A034BF0D0003000000F87D8A907CF124C05807A30C40F631C00000000000000840005EA33F689E22C08048698C39D92DC00000000000000840005EA33F689E22C0108FFE4D940F2DC00000000000000840	\N	\N
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.77678287975999183	614	613	329	01020000A034BF0D00020000003B548F320E5451C088FDF44BA63D2DC000000000000008403B548F320E5451C0A8AAA3CFEFAF27C00000000000000840	\N	\N
second_floor	\N	3.69828326745999147	615	614	613	01020000A034BF0D000300000089855B35799E51C044E93BEB08DE31C000000000000008403B548F320E5451C07823582DC9962DC000000000000008403B548F320E5451C088FDF44BA63D2DC00000000000000840	\N	\N
first_floor	\N	3.63916967176426942	616	309	612	01020000A034BF0D0002000000F87D8A907CF124C05807A30C40F631C09A9999999999E93FF87D8A907CF124C05807A30C40F631C00000000000000840	\N	\N
first_floor	\N	3.50436618393977728	617	311	614	01020000A034BF0D000200000089855B35799E51C044E93BEB08DE31C09A9999999999E93F89855B35799E51C044E93BEB08DE31C00000000000000840	\N	\N
first_floor	\N	0.604338199065438175	618	172	336	01020000A034BF0D00020000007FDC7F2D95B752C0F8BDA57F49EC2AC09A9999999999E93F83DC7F2D95B752C090BCA57F49EC2AC00000000000000840	\N	\N
\.


--
-- Data for Name: first_floor_edges_noded; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.first_floor_edges_noded (id, old_id, sub_id, source, target, geom) FROM stdin;
1	3	18	\N	\N	0102000020E6100000020000005BE8B5CC81C451C03A7541CC182F4540AE3EAACC81C451C024B35F28172F4540
2	3	35	\N	\N	0102000020E610000002000000AE3EAACC81C451C024B35F28172F4540F601147181C451C07FAC95A0162F4540
3	3	36	\N	\N	0102000020E610000002000000F601147181C451C07FAC95A0162F4540F1DF1D9680C451C0874CF25B152F4540
4	4	10	\N	\N	0102000020E610000002000000E82FB8CC81C451C0A16F521E192F45403D2DB8CC81C451C0D852F21D192F4540
5	4	12	\N	\N	0102000020E6100000020000003D2DB8CC81C451C0D852F21D192F4540592CB8CC81C451C02D57D21D192F4540
6	4	14	\N	\N	0102000020E610000002000000592CB8CC81C451C02D57D21D192F45409A2AB8CC81C451C0497D931D192F4540
7	4	16	\N	\N	0102000020E6100000020000009A2AB8CC81C451C0497D931D192F45403FEDB5CC81C451C0057CF1CC182F4540
8	4	18	\N	\N	0102000020E6100000020000003FEDB5CC81C451C0057CF1CC182F454033E9B5CC81C451C06AD15FCC182F4540
9	4	20	\N	\N	0102000020E61000000200000033E9B5CC81C451C06AD15FCC182F45405BE8B5CC81C451C03A7541CC182F4540
10	5	33	\N	\N	0102000020E610000004000000C0E842CD82C451C04E73C434272F45403C0B68A380C451C0B8249DFF232F454055C865A380C451C03247C7AD232F454055012D8A80C451C0E6566288232F4540
11	5	36	\N	\N	0102000020E61000000200000055012D8A80C451C0E6566288232F45406E4A068A80C451C01756B90E1E2F4540
12	5	43	\N	\N	0102000020E6100000030000006E4A068A80C451C01756B90E1E2F4540170B54C980C451C0ACEDCEB01D2F45407A8E49C980C451C000798D351C2F4540
13	5	62	\N	\N	0102000020E6100000050000007A8E49C980C451C000798D351C2F454053922DC881C451C0762E67BB1A2F4540B3C42AC881C451C08B7579561A2F45402DABC0CC81C451C01EE3AB4F1A2F4540CC34B8CC81C451C02577021F192F4540
14	5	64	\N	\N	0102000020E610000002000000CC34B8CC81C451C02577021F192F4540C030B8CC81C451C0F2CB701E192F4540
15	5	66	\N	\N	0102000020E610000002000000C030B8CC81C451C0F2CB701E192F4540E82FB8CC81C451C0A16F521E192F4540
16	6	2	\N	\N	0102000020E610000002000000F1DF1D9680C451C0874CF25B152F4540012F96E37FC451C0DF06FD5B152F4540
17	6	3	\N	\N	0102000020E610000002000000012F96E37FC451C0DF06FD5B152F45407DEA67527CC451C068E6335C152F4540
18	6	4	\N	\N	0102000020E6100000020000007DEA67527CC451C068E6335C152F454015321BA77BC451C086313E5C152F4540
19	7	28	\N	\N	0102000020E610000004000000DE78B5707AC451C08BA5C31E192F4540DBACBD707AC451C00F191D501A2F4540BACB44727AC451C003FD60521A2F454043C047727AC451C0365561C01A2F4540
20	7	33	\N	\N	0102000020E61000000200000043C047727AC451C0365561C01A2F45401D7C866D7BC451C03BA4E2341C2F4540
21	7	50	\N	\N	0102000020E6100000030000001D7C866D7BC451C03BA4E2341C2F454044B8906D7BC451C0EE1824B01D2F4540194D8FAD7BC451C04F76050F1E2F4540
22	7	54	\N	\N	0102000020E610000002000000194D8FAD7BC451C04F76050F1E2F45402E3DA2AD7BC451C077C8F3CB202F4540
23	7	55	\N	\N	0102000020E6100000020000002E3DA2AD7BC451C077C8F3CB202F4540CB2BB5AD7BC451C027C4AB88232F4540
24	7	56	\N	\N	0102000020E610000003000000CB2BB5AD7BC451C027C4AB88232F4540E08F02947BC451C0E982CBAE232F4540A5C504947BC451C07360A100242F4540
25	8	10	\N	\N	0102000020E6100000020000007944B3707AC451C021ABB2CC182F4540DF46B3707AC451C0D3E80BCD182F4540
26	8	12	\N	\N	0102000020E610000002000000DF46B3707AC451C0D3E80BCD182F4540A047B3707AC451C07F0A28CD182F4540
27	8	14	\N	\N	0102000020E610000002000000A047B3707AC451C07F0A28CD182F45409C74B5707AC451C02537251E192F4540
28	8	16	\N	\N	0102000020E6100000020000009C74B5707AC451C02537251E192F45407F76B5707AC451C099576B1E192F4540
29	8	18	\N	\N	0102000020E6100000020000007F76B5707AC451C099576B1E192F45401178B5707AC451C065E4A51E192F4540
30	8	20	\N	\N	0102000020E6100000020000001178B5707AC451C065E4A51E192F4540DE78B5707AC451C08BA5C31E192F4540
31	9	26	\N	\N	0102000020E61000000200000015321BA77BC451C086313E5C152F45408C128BC67AC451C05A9E65A9162F4540
32	9	27	\N	\N	0102000020E6100000020000008C128BC67AC451C05A9E65A9162F4540D0FCA7707AC451C003E9D028172F4540
33	9	46	\N	\N	0102000020E610000002000000D0FCA7707AC451C003E9D028172F45403740B3707AC451C0803C14CC182F4540
34	9	48	\N	\N	0102000020E6100000020000003740B3707AC451C0803C14CC182F45401A42B3707AC451C00E5D5ACC182F4540
35	9	50	\N	\N	0102000020E6100000020000001A42B3707AC451C00E5D5ACC182F4540AC43B3707AC451C0EFE994CC182F4540
36	9	52	\N	\N	0102000020E610000002000000AC43B3707AC451C0EFE994CC182F45407944B3707AC451C021ABB2CC182F4540
37	10	8	\N	\N	0102000020E61000000200000015321BA77BC451C086313E5C152F45408765CD937BC451C08C553F5C152F4540
38	10	9	\N	\N	0102000020E6100000020000008765CD937BC451C08C553F5C152F4540F440A7707AC451C0F789505C152F4540
39	10	11	\N	\N	0102000020E610000002000000F440A7707AC451C0F789505C152F4540ED42A6707AC451C0068A505C152F4540
40	10	12	\N	\N	0102000020E610000002000000ED42A6707AC451C0068A505C152F4540D17EA96B7AC451C079D5505C152F4540
41	10	13	\N	\N	0102000020E610000002000000D17EA96B7AC451C079D5505C152F454037EBAB457AC451C02F14535C152F4540
42	10	16	\N	\N	0102000020E61000000200000037EBAB457AC451C02F14535C152F454040AE134479C451C0004D625C152F4540
43	11	34	\N	\N	0102000020E61000000200000029ACAD0D78C451C0598DE71E192F4540EEACAD0D78C451C08995041F192F4540
44	11	36	\N	\N	0102000020E610000002000000EEACAD0D78C451C08995041F192F45403EAFAD0D78C451C0ED985B1F192F4540
45	11	38	\N	\N	0102000020E6100000020000003EAFAD0D78C451C0ED985B1F192F4540F9AFAD0D78C451C0A401771F192F4540
46	11	40	\N	\N	0102000020E610000004000000F9AFAD0D78C451C0A401771F192F454008C9B50D78C451C0DE0041501A2F454027C92E0C78C451C0C71285521A2F454052B5310C78C451C0FC6A85C01A2F4540
47	11	41	\N	\N	0102000020E61000000200000052B5310C78C451C0FC6A85C01A2F4540CDB8A2F176C451C09551B6631C2F4540
48	11	58	\N	\N	0102000020E610000002000000CDB8A2F176C451C09551B6631C2F4540A58BC0F176C451C0B9FF0BCC202F4540
49	11	59	\N	\N	0102000020E610000002000000A58BC0F176C451C0B9FF0BCC202F45404095C0F176C451C0CC6B77CD202F4540
50	11	62	\N	\N	0102000020E6100000020000004095C0F176C451C0CC6B77CD202F4540DE9EC1F176C451C0B3B9B8F4202F4540
51	11	65	\N	\N	0102000020E610000002000000DE9EC1F176C451C0B3B9B8F4202F45400048CAF176C451C031D7623C222F4540
52	11	66	\N	\N	0102000020E6100000020000000048CAF176C451C031D7623C222F45406A3FD6F176C451C081C91E01242F4540
53	11	67	\N	\N	0102000020E6100000020000006A3FD6F176C451C081C91E01242F4540CB41D6F176C451C073D17801242F4540
54	11	68	\N	\N	0102000020E610000002000000CB41D6F176C451C073D17801242F45400D83D6F176C451C065C91D0B242F4540
55	12	10	\N	\N	0102000020E610000002000000FB7DAB0D78C451C0EE92D6CC182F4540C07EAB0D78C451C0FD9AF3CC182F4540
56	12	12	\N	\N	0102000020E610000002000000C07EAB0D78C451C0FD9AF3CC182F45401081AB0D78C451C0FC9D4ACD182F4540
57	12	14	\N	\N	0102000020E6100000020000001081AB0D78C451C0FC9D4ACD182F4540CB81AB0D78C451C0900666CD182F4540
58	12	16	\N	\N	0102000020E610000002000000CB81AB0D78C451C0900666CD182F4540D2A8AD0D78C451C0C8E5691E192F4540
59	12	18	\N	\N	0102000020E610000002000000D2A8AD0D78C451C0C8E5691E192F4540A4AAAD0D78C451C0C865AE1E192F4540
60	12	20	\N	\N	0102000020E610000002000000A4AAAD0D78C451C0C865AE1E192F454029ACAD0D78C451C0598DE71E192F4540
61	13	27	\N	\N	0102000020E61000000200000040AE134479C451C0004D625C152F45409C8C623379C451C065C02575152F4540
62	13	29	\N	\N	0102000020E6100000020000009C8C623379C451C065C02575152F45409AA1C11F79C451C005864492152F4540
63	13	31	\N	\N	0102000020E6100000020000009AA1C11F79C451C005864492152F45407F219F7B78C451C05387C585162F4540
64	13	33	\N	\N	0102000020E6100000020000007F219F7B78C451C05387C585162F45401C56A00D78C451C0CED0F428172F4540
65	13	50	\N	\N	0102000020E6100000020000001C56A00D78C451C0CED0F428172F4540A47AAB0D78C451C0FAEA58CC182F4540
66	13	52	\N	\N	0102000020E610000002000000A47AAB0D78C451C0FAEA58CC182F4540767CAB0D78C451C02F6B9DCC182F4540
67	13	54	\N	\N	0102000020E610000002000000767CAB0D78C451C02F6B9DCC182F4540FB7DAB0D78C451C0EE92D6CC182F4540
68	14	3	\N	\N	0102000020E61000000200000040AE134479C451C0004D625C152F454077929F0D78C451C0777E745C152F4540
69	14	5	\N	\N	0102000020E61000000200000077929F0D78C451C0777E745C152F454013989E0D78C451C0857E745C152F4540
70	14	6	\N	\N	0102000020E61000000200000013989E0D78C451C0857E745C152F45404F8E590D78C451C09182745C152F4540
71	15	4	\N	\N	0102000020E6100000020000004F8E590D78C451C09182745C152F45403AF54E0D78C451C02F83745C152F4540
72	15	5	\N	\N	0102000020E6100000020000003AF54E0D78C451C02F83745C152F45404DD44D0D78C451C03F83745C152F4540
73	15	7	\N	\N	0102000020E6100000020000004DD44D0D78C451C03F83745C152F4540B9E59FF176C451C03300855C152F4540
74	15	8	\N	\N	0102000020E610000002000000B9E59FF176C451C03300855C152F45407228B0BE75C451C034D7965C152F4540
75	16	3	\N	\N	0102000020E6100000020000007228B0BE75C451C034D7965C152F4540BFB5A5BE75C451C0CED7965C152F4540
76	16	4	\N	\N	0102000020E610000002000000BFB5A5BE75C451C0CED7965C152F4540E898A4BE75C451C0DFD7965C152F4540
77	16	6	\N	\N	0102000020E610000002000000E898A4BE75C451C0DFD7965C152F4540ED4BCAA874C451C03DDDA65C152F4540
78	17	37	\N	\N	0102000020E6100000020000002EBD637273C451C0D5B92B1F192F454098BE637273C451C06330621F192F4540
79	17	39	\N	\N	0102000020E61000000200000098BE637273C451C06330621F192F454050BF637273C451C071D37D1F192F4540
80	17	41	\N	\N	0102000020E61000000200000050BF637273C451C071D37D1F192F454077C1637273C451C0AE89D01F192F4540
81	17	43	\N	\N	0102000020E61000000500000077C1637273C451C0AE89D01F192F45406FAD6B7273C451C05E2D85501A2F454039ADE47073C451C0C93EC9521A2F45405189E77073C451C0FF96C9C01A2F4540F01B127672C451C0D618E9341C2F4540
82	17	59	\N	\N	0102000020E610000003000000F01B127672C451C0D618E9341C2F4540A2EF1B7672C451C06225AEB01D2F45404E6DD13672C451C0623F930E1E2F4540
83	17	63	\N	\N	0102000020E6100000020000004E6DD13672C451C0623F930E1E2F4540F791E33672C451C08F0A90CC202F4540
84	17	64	\N	\N	0102000020E610000002000000F791E33672C451C08F0A90CC202F45405F9BE33672C451C0CAE3FBCD202F4540
85	17	67	\N	\N	0102000020E6100000020000005F9BE33672C451C0CAE3FBCD202F4540189FE43672C451C0DAF33CF5202F4540
86	17	70	\N	\N	0102000020E610000002000000189FE43672C451C0DAF33CF5202F45400E17ED3672C451C0548EE63C222F4540
87	17	71	\N	\N	0102000020E6100000020000000E17ED3672C451C0548EE63C222F4540D6BAF53672C451C06BAD2F8B232F4540
88	17	73	\N	\N	0102000020E610000003000000D6BAF53672C451C06BAD2F8B232F454054712E5072C451C09FB794B0232F45409189305072C451C0A0B29601242F4540
89	17	74	\N	\N	0102000020E6100000020000009189305072C451C0A0B29601242F4540098C305072C451C00A2CF601242F4540
90	18	11	\N	\N	0102000020E610000002000000FD9A617273C451C069BF1ACD182F4540679C617273C451C0E53551CD182F4540
91	18	13	\N	\N	0102000020E610000002000000679C617273C451C0E53551CD182F45401F9D617273C451C0EAD86CCD182F4540
92	18	15	\N	\N	0102000020E6100000020000001F9D617273C451C0EAD86CCD182F4540469F617273C451C00B8FBFCD182F4540
93	18	17	\N	\N	0102000020E610000002000000469F617273C451C00B8FBFCD182F4540F39F617273C451C09592D9CD182F4540
94	18	18	\N	\N	0102000020E610000002000000F39F617273C451C09592D9CD182F454088B8637273C451C0E3E0781E192F4540
95	18	20	\N	\N	0102000020E61000000200000088B8637273C451C0E3E0781E192F45407BBB637273C451C02C5DEA1E192F4540
96	18	22	\N	\N	0102000020E6100000020000007BBB637273C451C02C5DEA1E192F45402EBD637273C451C0D5B92B1F192F4540
97	19	22	\N	\N	0102000020E610000002000000ED4BCAA874C451C03DDDA65C152F45408500223374C451C04DDC330B162F4540
98	19	23	\N	\N	0102000020E6100000020000008500223374C451C04DDC330B162F4540CBEC5A8973C451C0808E1307172F4540
99	19	24	\N	\N	0102000020E610000002000000CBEC5A8973C451C0808E1307172F454079B0567273C451C045FD3829172F4540
100	19	40	\N	\N	0102000020E61000000200000079B0567273C451C045FD3829172F45405796617273C451C094E667CC182F4540
101	19	42	\N	\N	0102000020E6100000020000005796617273C451C094E667CC182F45404A99617273C451C0CA62D9CC182F4540
102	19	44	\N	\N	0102000020E6100000020000004A99617273C451C0CA62D9CC182F4540FD9A617273C451C069BF1ACD182F4540
103	20	9	\N	\N	0102000020E610000002000000ED4BCAA874C451C03DDDA65C152F4540FF8A199C73C451C0DA1EB65C152F4540
104	20	12	\N	\N	0102000020E610000002000000FF8A199C73C451C0DA1EB65C152F4540845FC87573C451C0D24BB85C152F4540
105	20	13	\N	\N	0102000020E610000002000000845FC87573C451C0D24BB85C152F4540B313567273C451C0EB7DB85C152F4540
106	20	15	\N	\N	0102000020E610000002000000B313567273C451C0EB7DB85C152F4540BB1B557273C451C0F97DB85C152F4540
107	20	16	\N	\N	0102000020E610000002000000BB1B557273C451C0F97DB85C152F4540C553FB4F72C451C06FFAC85C152F4540
108	20	17	\N	\N	0102000020E610000002000000C553FB4F72C451C06FFAC85C152F4540AE59AD9771C451C07071D35C152F4540
109	20	18	\N	\N	0102000020E610000002000000AE59AD9771C451C07071D35C152F45402563F9496FC451C035EDF45C152F4540
110	21	34	\N	\N	0102000020E6100000020000006E3092136EC451C08655791F192F4540FE3192136EC451C07009B71F192F4540
111	21	36	\N	\N	0102000020E610000002000000FE3192136EC451C07009B71F192F45404B3392136EC451C0685CEA1F192F4540
112	21	38	\N	\N	0102000020E6100000020000004B3392136EC451C0685CEA1F192F4540F43392136EC451C0185F0420192F4540
113	21	40	\N	\N	0102000020E610000003000000F43392136EC451C0185F0420192F45406DD39C136EC451C067175BC31A2F45404FE09C136EC451C045AD57C51A2F4540
114	21	43	\N	\N	0102000020E6100000020000004FE09C136EC451C045AD57C51A2F45409651ABE66BC451C06EBD95FF1D2F4540
115	21	45	\N	\N	0102000020E6100000020000009651ABE66BC451C06EBD95FF1D2F4540C97A18146BC451C02325FA371F2F4540
116	21	48	\N	\N	0102000020E610000002000000C97A18146BC451C02325FA371F2F4540CAF2FFCC6AC451C0302D73A11F2F4540
117	21	64	\N	\N	0102000020E610000002000000CAF2FFCC6AC451C0302D73A11F2F4540CF7703CD6AC451C007ACA52E202F4540
118	21	67	\N	\N	0102000020E610000002000000CF7703CD6AC451C007ACA52E202F4540646C07CD6AC451C0D29353CD202F4540
119	21	68	\N	\N	0102000020E610000002000000646C07CD6AC451C0D29353CD202F45407A7507CD6AC451C02118C0CE202F4540
120	22	8	\N	\N	0102000020E610000002000000381C90136EC451C0185B68CD182F4540C81D90136EC451C0ED0EA6CD182F4540
121	22	10	\N	\N	0102000020E610000002000000C81D90136EC451C0ED0EA6CD182F4540151F90136EC451C0D061D9CD182F4540
122	22	12	\N	\N	0102000020E610000002000000151F90136EC451C0D061D9CD182F4540BE1F90136EC451C07664F3CD182F4540
123	22	14	\N	\N	0102000020E610000002000000BE1F90136EC451C07664F3CD182F4540B62D92136EC451C0ABF30D1F192F4540
124	22	16	\N	\N	0102000020E610000002000000B62D92136EC451C0ABF30D1F192F45406E3092136EC451C08655791F192F4540
125	23	18	\N	\N	0102000020E6100000020000002563F9496FC451C035EDF45C152F454071C1C5316FC451C05564DC80152F4540
126	23	21	\N	\N	0102000020E61000000200000071C1C5316FC451C05564DC80152F45403A7985136EC451C0EE988629172F4540
127	23	34	\N	\N	0102000020E6100000020000003A7985136EC451C0EE988629172F4540801990136EC451C02FF9FCCC182F4540
128	23	36	\N	\N	0102000020E610000002000000801990136EC451C02FF9FCCC182F4540381C90136EC451C0185B68CD182F4540
129	25	11	\N	\N	0102000020E610000002000000807414346BC451C0FB80F6F5202F45401C14834F6BC451C0C84444CD202F4540
130	25	22	\N	\N	0102000020E6100000020000001C14834F6BC451C0C84444CD202F45409955EA826BC451C0237141CD202F4540
131	26	23	\N	\N	0102000020E610000002000000807414346BC451C0FB80F6F5202F4540273146CC6BC451C091B29DD7212F4540
132	26	26	\N	\N	0102000020E610000002000000273146CC6BC451C091B29DD7212F4540FF2A780E6CC451C00DE6C239222F4540
133	26	46	\N	\N	0102000020E610000002000000FF2A780E6CC451C00DE6C239222F45403E43780E6CC451C07988893D222F4540
134	27	8	\N	\N	0102000020E6100000020000007A7507CD6AC451C02118C0CE202F4540FD23ECA76AC451C0E485CC05212F4540
135	27	11	\N	\N	0102000020E610000002000000FD23ECA76AC451C0E485CC05212F454019EAAA376AC451C0DDC554AC212F4540
136	27	12	\N	\N	0102000020E61000000200000019EAAA376AC451C0DDC554AC212F4540B2D7090D69C451C01E805A67232F4540
137	27	14	\N	\N	0102000020E610000002000000B2D7090D69C451C01E805A67232F45402FD368F968C451C0F1367984232F4540
138	27	16	\N	\N	0102000020E6100000020000002FD368F968C451C0F1367984232F45400AAC707768C451C07D1E4945242F4540
139	28	16	\N	\N	0102000020E6100000020000002563F9496FC451C035EDF45C152F4540ACE184136EC451C0D918065D152F4540
140	28	18	\N	\N	0102000020E610000002000000ACE184136EC451C0D918065D152F4540F2EF83136EC451C0E618065D152F4540
141	28	19	\N	\N	0102000020E610000002000000F2EF83136EC451C0E618065D152F45400AE667F66DC451C00DB5075D152F4540
142	28	20	\N	\N	0102000020E6100000020000000AE667F66DC451C00DB5075D152F45409A36C9196CC451C05E11225D152F4540
143	28	21	\N	\N	0102000020E6100000020000009A36C9196CC451C05E11225D152F45400EAF4A0E6CC451C01CB4225D152F4540
144	28	22	\N	\N	0102000020E6100000020000000EAF4A0E6CC451C01CB4225D152F45402003B8F36BC451C0592C245D152F4540
145	28	25	\N	\N	0102000020E6100000020000002003B8F36BC451C0592C245D152F45401DD9C1826BC451C0BD6B2A5D152F4540
146	28	26	\N	\N	0102000020E6100000020000001DD9C1826BC451C0BD6B2A5D152F4540FD67EB336BC451C0FAC72E5D152F4540
147	28	29	\N	\N	0102000020E610000002000000FD67EB336BC451C0FAC72E5D152F4540D7F3DECC6AC451C0037B345D152F4540
148	28	32	\N	\N	0102000020E610000002000000D7F3DECC6AC451C0037B345D152F4540D7A3B9D969C451C0A3ED415D152F4540
149	29	4	\N	\N	0102000020E610000002000000D7A3B9D969C451C0A3ED415D152F45405CBCAFD969C451C02DEE415D152F4540
150	29	5	\N	\N	0102000020E6100000020000005CBCAFD969C451C02DEE415D152F454059AEAED969C451C03BEE415D152F4540
151	29	7	\N	\N	0102000020E61000000200000059AEAED969C451C03BEE415D152F454089EE3C7768C451C07627555D152F4540
152	29	8	\N	\N	0102000020E61000000200000089EE3C7768C451C07627555D152F4540DD10836C67C451C0C79E635D152F4540
153	30	3	\N	\N	0102000020E610000002000000DD10836C67C451C0C79E635D152F45402152796C67C451C04D9F635D152F4540
154	30	4	\N	\N	0102000020E6100000020000002152796C67C451C04D9F635D152F45407548786C67C451C05B9F635D152F4540
155	30	6	\N	\N	0102000020E6100000020000007548786C67C451C05B9F635D152F4540AD16165566C451C020A4725D152F4540
156	31	51	\N	\N	0102000020E6100000020000007DD2AD1E65C451C0804AF61F192F4540D8D4AD1E65C451C0EA7E5720192F4540
157	31	53	\N	\N	0102000020E610000002000000D8D4AD1E65C451C0EA7E5720192F454031D6AD1E65C451C085188F20192F4540
158	31	55	\N	\N	0102000020E61000000400000031D6AD1E65C451C085188F20192F4540FA37B51E65C451C013BE4F511A2F4540BB362E1D65C451C0F7CD93531A2F4540D6E0301D65C451C0322694C11A2F4540
159	31	61	\N	\N	0102000020E610000002000000D6E0301D65C451C0322694C11A2F45400CDF504964C451C03DFFE5FB1B2F4540
160	31	68	\N	\N	0102000020E6100000030000000CDF504964C451C03DFFE5FB1B2F4540DA0A5A4964C451C08EFC21781D2F4540017BE1E463C451C082BD2E0D1E2F4540
161	31	76	\N	\N	0102000020E610000002000000017BE1E463C451C082BD2E0D1E2F45402EE7E3E463C451C08B20D3711E2F4540
162	31	77	\N	\N	0102000020E6100000020000002EE7E3E463C451C08B20D3711E2F4540B0A0EEE463C451C01A6B5D2F202F4540
163	31	80	\N	\N	0102000020E610000003000000B0A0EEE463C451C01A6B5D2F202F45405B73F2E463C451C050CD2ECE202F4540BF88FBE463C451C0AEB58B47222F4540
164	31	81	\N	\N	0102000020E610000002000000BF88FBE463C451C0AEB58B47222F4540456B03E563C451C09E221C8F232F4540
165	31	102	\N	\N	0102000020E610000003000000456B03E563C451C09E221C8F232F4540C15237FD63C451C01CADFEB2232F4540704539FD63C451C05899E103242F4540
166	32	4	\N	\N	0102000020E61000000200000098D5AB1E65C451C01150E5CD182F4540F3D7AB1E65C451C01F8446CE182F4540
167	32	6	\N	\N	0102000020E610000002000000F3D7AB1E65C451C01F8446CE182F45404CD9AB1E65C451C0841D7ECE182F4540
168	32	8	\N	\N	0102000020E6100000020000004CD9AB1E65C451C0841D7ECE182F45407DD2AD1E65C451C0804AF61F192F4540
169	33	8	\N	\N	0102000020E610000002000000AD16165566C451C020A4725D152F4540F0E8D4E465C451C063D6FA03162F4540
170	33	9	\N	\N	0102000020E610000002000000F0E8D4E465C451C063D6FA03162F4540E4A9A11E65C451C0DE8D032A172F4540
171	33	16	\N	\N	0102000020E610000002000000E4A9A11E65C451C0DE8D032A172F454098D5AB1E65C451C01150E5CD182F4540
172	34	17	\N	\N	0102000020E610000002000000AD16165566C451C020A4725D152F4540BAF81B7065C451C0CFA57E5D152F4540
173	34	20	\N	\N	0102000020E610000002000000BAF81B7065C451C0CFA57E5D152F45404F41512365C451C0A1AC825D152F4540
174	34	21	\N	\N	0102000020E6100000020000004F41512365C451C0A1AC825D152F45409D34A11E65C451C08EEB825D152F4540
175	34	23	\N	\N	0102000020E6100000020000009D34A11E65C451C08EEB825D152F4540204BA01E65C451C09AEB825D152F4540
176	34	24	\N	\N	0102000020E610000002000000204BA01E65C451C09AEB825D152F4540D21B08FD63C451C0FC1A925D152F4540
177	34	25	\N	\N	0102000020E610000002000000D21B08FD63C451C0FC1A925D152F4540A60C5A4C63C451C0A85E9B5D152F4540
178	34	26	\N	\N	0102000020E610000002000000A60C5A4C63C451C0A85E9B5D152F4540F90DD0155FC451C07AECD35D152F4540
179	34	27	\N	\N	0102000020E610000002000000F90DD0155FC451C07AECD35D152F45408DF7CA155FC451C0BEECD35D152F4540
180	34	29	\N	\N	0102000020E6100000020000008DF7CA155FC451C0BEECD35D152F4540E72A83BB5DC451C00E15E65D152F4540
181	34	34	\N	\N	0102000020E610000002000000E72A83BB5DC451C00E15E65D152F45404EE5007B5DC451C04E1199BD152F4540
182	35	20	\N	\N	0102000020E6100000020000004EE5007B5DC451C04E1199BD152F45406BDB6FFA5CC451C0029C9FBD152F4540
183	35	22	\N	\N	0102000020E6100000020000006BDB6FFA5CC451C0029C9FBD152F45400DA1A8CC5CC451C050F0A1BD152F4540
184	35	23	\N	\N	0102000020E6100000020000000DA1A8CC5CC451C050F0A1BD152F45405DA0CCAF5CC451C03C68A3BD152F4540
185	35	24	\N	\N	0102000020E6100000020000005DA0CCAF5CC451C03C68A3BD152F45402545A0505CC451C0F53FA8BD152F4540
186	35	26	\N	\N	0102000020E6100000020000002545A0505CC451C0F53FA8BD152F4540631CCD225CC451C0DE94AABD152F4540
187	35	28	\N	\N	0102000020E610000002000000631CCD225CC451C0DE94AABD152F45409DDDA51A5CC451C013FFAABD152F4540
188	35	31	\N	\N	0102000020E6100000020000009DDDA51A5CC451C013FFAABD152F45408A5E7E125CC451C04A69ABBD152F4540
189	35	33	\N	\N	0102000020E6100000020000008A5E7E125CC451C04A69ABBD152F454031009FF15BC451C07C15ADBD152F4540
190	35	35	\N	\N	0102000020E61000000200000031009FF15BC451C07C15ADBD152F45401BFCE2EC5BC451C02853ADBD152F4540
191	35	36	\N	\N	0102000020E6100000020000001BFCE2EC5BC451C02853ADBD152F454046E626635BC451C04855B4BD152F4540
192	35	39	\N	\N	0102000020E61000000200000046E626635BC451C04855B4BD152F45403ECED05B5BC451C0D8B4B4BD152F4540
193	35	40	\N	\N	0102000020E6100000020000003ECED05B5BC451C0D8B4B4BD152F4540E32FC92F5BC451C060F2B6BD152F4540
194	36	24	\N	\N	0102000020E610000002000000E32FC92F5BC451C060F2B6BD152F4540AD79A2F85AC451C019BBB9BD152F4540
195	36	25	\N	\N	0102000020E610000002000000AD79A2F85AC451C019BBB9BD152F454074854DD75AC451C0D969BBBD152F4540
196	36	28	\N	\N	0102000020E61000000200000074854DD75AC451C0D969BBBD152F4540D37E1F885AC451C01869BFBD152F4540
197	36	47	\N	\N	0102000020E610000002000000D37E1F885AC451C01869BFBD152F45402531F9645AC451C01D82A189152F4540
198	36	48	\N	\N	0102000020E6100000020000002531F9645AC451C01D82A189152F4540B1EE667158C451C059F2E8A4122F4540
199	37	30	\N	\N	0102000020E610000002000000B1EE667158C451C059F2E8A4122F45401FEABBE557C451C0C0C7EFA4122F4540
200	37	31	\N	\N	0102000020E6100000020000001FEABBE557C451C0C0C7EFA4122F4540C686B4E557C451C01CC8EFA4122F4540
201	37	33	\N	\N	0102000020E610000002000000C686B4E557C451C01CC8EFA4122F4540A3D2B3E557C451C025C8EFA4122F4540
202	37	35	\N	\N	0102000020E610000002000000A3D2B3E557C451C025C8EFA4122F4540ACFBACE557C451C07BC8EFA4122F4540
203	37	38	\N	\N	0102000020E610000002000000ACFBACE557C451C07BC8EFA4122F4540F004264F57C451C0E625F7A4122F4540
204	37	39	\N	\N	0102000020E610000002000000F004264F57C451C0E625F7A4122F45401A30B2E356C451C0C967FCA4122F4540
205	37	42	\N	\N	0102000020E6100000020000001A30B2E356C451C0C967FCA4122F4540BCE21ECB55C451C01C220AA5122F4540
206	37	43	\N	\N	0102000020E610000002000000BCE21ECB55C451C01C220AA5122F45403194B9B655C451C093210BA5122F4540
207	37	45	\N	\N	0102000020E6100000020000003194B9B655C451C093210BA5122F4540C3E4B8B655C451C09C210BA5122F4540
208	37	47	\N	\N	0102000020E610000002000000C3E4B8B655C451C09C210BA5122F45408B90BA2E55C451C0FCC811A5122F4540
209	37	48	\N	\N	0102000020E6100000020000008B90BA2E55C451C0FCC811A5122F4540218AD6D254C451C0F44716A5122F4540
210	37	50	\N	\N	0102000020E610000002000000218AD6D254C451C0F44716A5122F4540164A51D254C451C0794E16A5122F4540
211	37	52	\N	\N	0102000020E610000002000000164A51D254C451C0794E16A5122F45406E8441D254C451C03F4F16A5122F4540
212	37	54	\N	\N	0102000020E6100000020000006E8441D254C451C03F4F16A5122F4540EF05986054C451C0E9DE1BA5122F4540
213	37	56	\N	\N	0102000020E610000002000000EF05986054C451C0E9DE1BA5122F4540B975055354C451C0EA881CA5122F4540
214	37	58	\N	\N	0102000020E610000002000000B975055354C451C0EA881CA5122F454006C9F55254C451C0AE891CA5122F4540
215	37	60	\N	\N	0102000020E61000000200000006C9F55254C451C0AE891CA5122F45409902FEDF51C451C0B8363BA5122F4540
216	38	110	\N	\N	0102000020E6100000020000009902FEDF51C451C0B8363BA5122F454012AEBE4B51C451C024392781132F4540
217	38	112	\N	\N	0102000020E61000000200000012AEBE4B51C451C024392781132F4540F9398C4351C451C0413C508D132F4540
218	38	114	\N	\N	0102000020E610000002000000F9398C4351C451C0413C508D132F4540B5264B1051C451C0E91359D9132F4540
219	38	117	\N	\N	0102000020E610000002000000B5264B1051C451C0E91359D9132F45408362CBCB50C451C0D005F73E142F4540
220	38	123	\N	\N	0102000020E6100000020000008362CBCB50C451C0D005F73E142F45409858F9CB50C451C02F0684841C2F4540
221	38	126	\N	\N	0102000020E6100000020000009858F9CB50C451C02F0684841C2F4540F758F9CB50C451C0910095841C2F4540
222	38	128	\N	\N	0102000020E610000002000000F758F9CB50C451C0910095841C2F45401559F9CB50C451C0FF6C9A841C2F4540
223	38	130	\N	\N	0102000020E6100000020000001559F9CB50C451C0FF6C9A841C2F45400D9B00CC50C451C0A1C0FBD21D2F4540
224	38	133	\N	\N	0102000020E6100000020000000D9B00CC50C451C0A1C0FBD21D2F4540CD9B00CC50C451C04E431ED31D2F4540
225	38	134	\N	\N	0102000020E610000002000000CD9B00CC50C451C04E431ED31D2F454063D000CC50C451C02A0495DC1D2F4540
226	38	135	\N	\N	0102000020E61000000200000063D000CC50C451C02A0495DC1D2F45400AD100CC50C451C0260FB3DC1D2F4540
227	38	138	\N	\N	0102000020E6100000020000000AD100CC50C451C0260FB3DC1D2F45401D1704CC50C451C06B3A87731E2F4540
228	38	139	\N	\N	0102000020E6100000020000001D1704CC50C451C06B3A87731E2F4540936604CC50C451C01F48D4811E2F4540
229	38	140	\N	\N	0102000020E610000002000000936604CC50C451C01F48D4811E2F454047570BCC50C451C0A96D95C11F2F4540
230	38	143	\N	\N	0102000020E61000000200000047570BCC50C451C0A96D95C11F2F4540EFC20DCC50C451C0DC7A1A31202F4540
231	38	146	\N	\N	0102000020E610000002000000EFC20DCC50C451C0DC7A1A31202F4540C14811CC50C451C0CDB567D3202F4540
232	38	147	\N	\N	0102000020E610000002000000C14811CC50C451C0CDB567D3202F4540206619CC50C451C0D3594549222F4540
233	38	148	\N	\N	0102000020E610000002000000206619CC50C451C0D3594549222F45404AA126CC50C451C0417BDCAA242F4540
234	38	151	\N	\N	0102000020E6100000020000004AA126CC50C451C0417BDCAA242F45407CA126CC50C451C0C790E5AA242F4540
235	38	154	\N	\N	0102000020E6100000020000007CA126CC50C451C0C790E5AA242F4540F7A126CC50C451C08FA7FBAA242F4540
236	38	157	\N	\N	0102000020E610000002000000F7A126CC50C451C08FA7FBAA242F4540D9C126CC50C451C0ACA2B8B0242F4540
237	38	160	\N	\N	0102000020E610000002000000D9C126CC50C451C0ACA2B8B0242F454047C226CC50C451C0F657CCB0242F4540
238	38	163	\N	\N	0102000020E61000000200000047C226CC50C451C0F657CCB0242F454073C226CC50C451C08353D4B0242F4540
239	38	166	\N	\N	0102000020E61000000200000073C226CC50C451C08353D4B0242F4540F93932CC50C451C0893B23C1262F4540
240	38	167	\N	\N	0102000020E610000002000000F93932CC50C451C0893B23C1262F4540CFAE32CC50C451C0C3362AD6262F4540
241	38	168	\N	\N	0102000020E610000002000000CFAE32CC50C451C0C3362AD6262F45404A1835CC50C451C0D6FD4A45272F4540
242	38	170	\N	\N	0102000020E6100000020000004A1835CC50C451C0D6FD4A45272F4540BE1835CC50C451C0F7EB5F45272F4540
243	38	172	\N	\N	0102000020E610000002000000BE1835CC50C451C0F7EB5F45272F45402B1935CC50C451C03FA17345272F4540
244	38	174	\N	\N	0102000020E6100000020000002B1935CC50C451C03FA17345272F4540911935CC50C451C06AD48545272F4540
245	38	176	\N	\N	0102000020E610000002000000911935CC50C451C06AD48545272F4540A41935CC50C451C0CB3F8945272F4540
246	38	178	\N	\N	0102000020E610000002000000A41935CC50C451C0CB3F8945272F4540994135CC50C451C0C94DBA4C272F4540
247	38	180	\N	\N	0102000020E610000002000000994135CC50C451C0C94DBA4C272F4540A04135CC50C451C0C593BB4C272F4540
248	38	182	\N	\N	0102000020E610000002000000A04135CC50C451C0C593BB4C272F4540164235CC50C451C0B5B9D04C272F4540
249	38	184	\N	\N	0102000020E610000002000000164235CC50C451C0B5B9D04C272F4540914235CC50C451C07ED0E64C272F4540
250	38	186	\N	\N	0102000020E610000002000000914235CC50C451C07ED0E64C272F45400F4335CC50C451C06594FD4C272F4540
251	38	188	\N	\N	0102000020E6100000020000000F4335CC50C451C06594FD4C272F454046C535CC50C451C0D9E86C64272F4540
252	38	191	\N	\N	0102000020E61000000200000046C535CC50C451C0D9E86C64272F4540F19136CC50C451C059694289272F4540
253	38	193	\N	\N	0102000020E610000002000000F19136CC50C451C059694289272F4540659236CC50C451C07A575789272F4540
254	38	195	\N	\N	0102000020E610000002000000659236CC50C451C07A575789272F4540D39236CC50C451C0C40C6B89272F4540
255	38	197	\N	\N	0102000020E610000002000000D39236CC50C451C0C40C6B89272F45403E9336CC50C451C0116F7E89272F4540
256	38	199	\N	\N	0102000020E6100000020000003E9336CC50C451C0116F7E89272F4540429336CC50C451C05B057F89272F4540
257	38	201	\N	\N	0102000020E610000002000000429336CC50C451C05B057F89272F454044BB36CC50C451C0BD65B290272F4540
258	38	203	\N	\N	0102000020E61000000200000044BB36CC50C451C0BD65B290272F4540BDBB36CC50C451C03725C890272F4540
259	38	205	\N	\N	0102000020E610000002000000BDBB36CC50C451C03725C890272F454038BC36CC50C451C0013CDE90272F4540
260	38	207	\N	\N	0102000020E61000000200000038BC36CC50C451C0013CDE90272F4540B6BC36CC50C451C0E9FFF490272F4540
261	38	209	\N	\N	0102000020E610000002000000B6BC36CC50C451C0E9FFF490272F454071D636CC50C451C0B97C9695272F4540
262	38	212	\N	\N	0102000020E61000000200000071D636CC50C451C0B97C9695272F454005EF45CC50C451C0BA42194D2A2F4540
263	38	213	\N	\N	0102000020E61000000200000005EF45CC50C451C0BA42194D2A2F45408C0F46CC50C451C065C2F3522A2F4540
264	38	214	\N	\N	0102000020E6100000020000008C0F46CC50C451C065C2F3522A2F45407F1046CC50C451C034821F532A2F4540
265	38	215	\N	\N	0102000020E6100000020000007F1046CC50C451C034821F532A2F45407A1A46CC50C451C0CC52EB542A2F4540
266	38	216	\N	\N	0102000020E6100000020000007A1A46CC50C451C0CC52EB542A2F4540743946CC50C451C07E807E5A2A2F4540
267	38	217	\N	\N	0102000020E610000002000000743946CC50C451C07E807E5A2A2F4540EE3946CC50C451C04B97945A2A2F4540
268	38	218	\N	\N	0102000020E610000002000000EE3946CC50C451C04B97945A2A2F4540B25846CC50C451C03F081E602A2F4540
269	38	219	\N	\N	0102000020E610000002000000B25846CC50C451C03F081E602A2F4540134B47CC50C451C00303BD8B2A2F4540
270	38	220	\N	\N	0102000020E610000002000000134B47CC50C451C00303BD8B2A2F454045B265CC50C451C0A9557C04302F4540
271	39	6	\N	\N	0102000020E61000000200000045B265CC50C451C0A9557C04302F45400AB365CC50C451C04FB59F04302F4540
272	39	7	\N	\N	0102000020E6100000020000000AB365CC50C451C04FB59F04302F454022B365CC50C451C0020EA404302F4540
273	39	9	\N	\N	0102000020E61000000200000022B365CC50C451C0020EA404302F4540B65A66CC50C451C07DC8CC22302F4540
274	39	11	\N	\N	0102000020E610000002000000B65A66CC50C451C07DC8CC22302F4540D25A66CC50C451C01DE4D122302F4540
275	39	12	\N	\N	0102000020E610000002000000D25A66CC50C451C01DE4D122302F45409C5B66CC50C451C0B828F622302F4540
276	41	25	\N	\N	0102000020E61000000300000085638BB84CC451C04E692723302F4540BC2F5BEC4BC451C0F0E83023302F45401C898AD44BC451C0B7033223302F4540
277	41	27	\N	\N	0102000020E6100000020000001C898AD44BC451C0B7033223302F4540ECE389D44BC451C0BF033223302F4540
278	41	29	\N	\N	0102000020E610000002000000ECE389D44BC451C0BF033223302F45403D1633C04BC451C040F53223302F4540
279	41	30	\N	\N	0102000020E6100000020000003D1633C04BC451C040F53223302F45405A4E66B74BC451C0BD5D3323302F4540
280	41	36	\N	\N	0102000020E6100000030000005A4E66B74BC451C0BD5D3323302F4540C6DCD2A14AC451C0BD1EF8BE312F4540CB94078F47C451C00BEE1BBF312F4540
281	41	37	\N	\N	0102000020E610000002000000CB94078F47C451C00BEE1BBF312F45402B07018F47C451C057EE1BBF312F4540
282	41	39	\N	\N	0102000020E6100000020000002B07018F47C451C057EE1BBF312F45406867008F47C451C05FEE1BBF312F4540
283	41	41	\N	\N	0102000020E6100000020000006867008F47C451C05FEE1BBF312F45405637FA8E47C451C0A7EE1BBF312F4540
284	41	44	\N	\N	0102000020E6100000020000005637FA8E47C451C0A7EE1BBF312F454038AFD8FE46C451C0FD7D22BF312F4540
285	41	47	\N	\N	0102000020E61000000200000038AFD8FE46C451C0FD7D22BF312F4540045036B546C451C0EFD725BF312F4540
286	41	50	\N	\N	0102000020E610000002000000045036B546C451C0EFD725BF312F454005D583A246C451C0C9B126BF312F4540
287	43	6	\N	\N	0102000020E6100000020000009C5B66CC50C451C0B828F622302F4540A40E66CC50C451C0BC28F622302F4540
288	43	8	\N	\N	0102000020E610000002000000A40E66CC50C451C0BC28F622302F454065F8F55D4EC451C030A31323302F4540
289	43	11	\N	\N	0102000020E61000000200000065F8F55D4EC451C030A31323302F45408B33E55D4EC451C0FBA31323302F4540
290	43	12	\N	\N	0102000020E6100000030000008B33E55D4EC451C0FBA31323302F4540EB3E08044EC451C07CE51723302F4540240BD8374DC451C090772123302F4540
291	44	39	\N	\N	0102000020E6100000030000006F8332D354C451C05C8F4A04302F45406CB6629F55C451C0E9904004302F45408CF214B755C451C03D673F04302F4540
292	44	41	\N	\N	0102000020E6100000020000008CF214B755C451C03D673F04302F45405BA115B755C451C034673F04302F4540
293	44	43	\N	\N	0102000020E6100000020000005BA115B755C451C034673F04302F45406168F9BF55C451C088F73E04302F4540
294	44	54	\N	\N	0102000020E6100000020000006168F9BF55C451C088F73E04302F454055CB31C655C451C02DFF770D302F4540
295	44	55	\N	\N	0102000020E61000000300000055CB31C655C451C02DFF770D302F4540717FFCEE56C451C08A8A85C5312F4540A5DEB6FC59C451C0BA855EC5312F4540
296	44	58	\N	\N	0102000020E610000002000000A5DEB6FC59C451C0BA855EC5312F4540AFB7BDFC59C451C062855EC5312F4540
297	44	60	\N	\N	0102000020E610000002000000AFB7BDFC59C451C062855EC5312F4540096CBEFC59C451C059855EC5312F4540
298	44	62	\N	\N	0102000020E610000002000000096CBEFC59C451C059855EC5312F4540DFD1C5FC59C451C0FB845EC5312F4540
299	44	63	\N	\N	0102000020E610000002000000DFD1C5FC59C451C0FB845EC5312F454052A34F7E5AC451C0C10D58C5312F4540
300	44	66	\N	\N	0102000020E61000000200000052A34F7E5AC451C0C10D58C5312F45407333D39F5AC451C0856156C5312F4540
301	44	78	\N	\N	0102000020E6100000030000007333D39F5AC451C0856156C5312F4540D40E31B95AC451C061C0F2EA312F4540E181FDF85AC451C0F787EFEA312F4540
302	46	5	\N	\N	0102000020E61000000200000045B265CC50C451C0A9557C04302F4540C2FD65CC50C451C0A5557C04302F4540
303	46	7	\N	\N	0102000020E610000002000000C2FD65CC50C451C0A5557C04302F4540A55266CC50C451C0A1557C04302F4540
304	46	8	\N	\N	0102000020E610000002000000A55266CC50C451C0A1557C04302F4540517658E051C451C07B0E6F04302F4540
305	46	10	\N	\N	0102000020E610000003000000517658E051C451C07B0E6F04302F45403FCCC39453C451C0970E5A04302F45403DFFF36054C451C0DD215004302F4540
306	47	23	\N	\N	0102000020E6100000020000009902FEDF51C451C0B8363BA5122F4540C7D580D551C451C0A4D2AD95122F4540
307	47	31	\N	\N	0102000020E610000002000000C7D580D551C451C0A4D2AD95122F4540DAC30CCC50C451C0DD71BA95122F4540
308	47	32	\N	\N	0102000020E610000002000000DAC30CCC50C451C0DD71BA95122F4540B76D0CCC50C451C0E171BA95122F4540
309	47	35	\N	\N	0102000020E610000002000000B76D0CCC50C451C0E171BA95122F45401E210CCC50C451C0E571BA95122F4540
310	47	37	\N	\N	0102000020E6100000020000001E210CCC50C451C0E571BA95122F4540A4EE80BF50C451C0950ABB95122F4540
311	47	40	\N	\N	0102000020E610000002000000A4EE80BF50C451C0950ABB95122F45404DB472BF50C451C0420BBB95122F4540
312	47	43	\N	\N	0102000020E6100000020000004DB472BF50C451C0420BBB95122F45402AE965BF50C451C0DE0BBB95122F4540
313	47	46	\N	\N	0102000020E6100000020000002AE965BF50C451C0DE0BBB95122F45401F669C5D4EC451C07C0AD895122F4540
314	48	30	\N	\N	0102000020E6100000020000001F669C5D4EC451C07C0AD895122F45407A318B5D4EC451C0480BD895122F4540
315	48	31	\N	\N	0102000020E6100000020000007A318B5D4EC451C0480BD895122F454064DB8A5D4EC451C04C0BD895122F4540
316	48	33	\N	\N	0102000020E61000000200000064DB8A5D4EC451C04C0BD895122F4540806FEE2B4DC451C09936E695122F4540
317	48	35	\N	\N	0102000020E610000002000000806FEE2B4DC451C09936E695122F4540A5D7D02B4DC451C0F937E695122F4540
318	48	37	\N	\N	0102000020E610000002000000A5D7D02B4DC451C0F937E695122F45404184A2AC4CC451C07C1DEC95122F4540
319	48	39	\N	\N	0102000020E6100000020000004184A2AC4CC451C07C1DEC95122F4540B31C85AC4CC451C0D91EEC95122F4540
320	48	41	\N	\N	0102000020E610000002000000B31C85AC4CC451C0D91EEC95122F4540D664842249C451C035201696122F4540
321	48	44	\N	\N	0102000020E610000003000000D664842249C451C035201696122F454002F31C1B49C451C04FF211A1122F454089BA60F248C451C00FCE13A1122F4540
322	48	49	\N	\N	0102000020E61000000200000089BA60F248C451C00FCE13A1122F4540BCAB5A3647C451C089B1C433152F4540
323	48	55	\N	\N	0102000020E610000002000000BCAB5A3647C451C089B1C433152F45407C8A01FA46C451C0CFD84534152F4540
324	48	58	\N	\N	0102000020E6100000040000007C8A01FA46C451C0CFD84534152F4540902E7F4644C451C0ABC50D3A152F45400FC252BC42C451C0A322CA82172F4540115E67BC42C451C0BA95328B1B2F4540
325	48	60	\N	\N	0102000020E610000003000000115E67BC42C451C0BA95328B1B2F4540CBA0E47B42C451C07E3DE5EA1B2F4540F7B6E77B42C451C02C23C2851C2F4540
326	49	14	\N	\N	0102000020E610000002000000C39A808844C451C060FEAA851C2F4540C318169C44C451C02E1FAA851C2F4540
327	49	15	\N	\N	0102000020E610000003000000C318169C44C451C02E1FAA851C2F4540CBFA256E45C451C027C5A0851C2F4540BF8F519445C451C007109F851C2F4540
328	49	16	\N	\N	0102000020E610000002000000BF8F519445C451C007109F851C2F45409CCB331D46C451C072F098851C2F4540
329	49	23	\N	\N	0102000020E6100000020000009CCB331D46C451C072F098851C2F45406FB7098246C451C03C731C1B1D2F4540
330	49	25	\N	\N	0102000020E6100000020000006FB7098246C451C03C731C1B1D2F45402F971CB246C451C0D96D64621D2F4540
331	49	26	\N	\N	0102000020E6100000020000002F971CB246C451C0D96D64621D2F4540BC07BDE746C451C0E43AE8B11D2F4540
332	49	28	\N	\N	0102000020E610000002000000BC07BDE746C451C0E43AE8B11D2F4540A3A99EFE46C451C0C09DD5D31D2F4540
333	52	19	\N	\N	0102000020E610000002000000A3A99EFE46C451C0C09DD5D31D2F4540F331C08E47C451C07A0ECFD31D2F4540
334	52	22	\N	\N	0102000020E610000002000000F331C08E47C451C07A0ECFD31D2F45401862C68E47C451C0320ECFD31D2F4540
335	52	24	\N	\N	0102000020E6100000020000001862C68E47C451C0320ECFD31D2F4540DC01C78E47C451C02B0ECFD31D2F4540
336	52	26	\N	\N	0102000020E610000002000000DC01C78E47C451C02B0ECFD31D2F4540918FCD8E47C451C0DE0DCFD31D2F4540
337	52	27	\N	\N	0102000020E610000002000000918FCD8E47C451C0DE0DCFD31D2F454064BA44C448C451C047F8C0D31D2F4540
338	52	30	\N	\N	0102000020E61000000200000064BA44C448C451C047F8C0D31D2F4540FAC867A549C451C033B9B6D31D2F4540
339	52	33	\N	\N	0102000020E610000002000000FAC867A549C451C033B9B6D31D2F4540C6256EA549C451C0E9B8B6D31D2F4540
340	52	35	\N	\N	0102000020E610000002000000C6256EA549C451C0E9B8B6D31D2F454009CA6EA549C451C0E2B8B6D31D2F4540
341	52	37	\N	\N	0102000020E61000000200000009CA6EA549C451C0E2B8B6D31D2F4540068775A549C451C093B8B6D31D2F4540
342	52	38	\N	\N	0102000020E610000002000000068775A549C451C093B8B6D31D2F4540CCB310424AC451C0F497AFD31D2F4540
343	53	4	\N	\N	0102000020E610000002000000A3A99EFE46C451C0C09DD5D31D2F4540E878C72346C451C0381F79181F2F4540
344	53	8	\N	\N	0102000020E610000002000000E878C72346C451C0381F79181F2F454038F0CA2346C451C0544B82C21F2F4540
345	54	19	\N	\N	0102000020E61000000200000038F0CA2346C451C0544B82C21F2F4540F399AC3A46C451C0D2B76FE41F2F4540
346	54	21	\N	\N	0102000020E610000002000000F399AC3A46C451C0D2B76FE41F2F4540CFE3CB5646C451C05C6E220E202F4540
347	54	29	\N	\N	0102000020E610000002000000CFE3CB5646C451C05C6E220E202F4540BA27E15646C451C0AD411620242F4540
348	54	30	\N	\N	0102000020E610000002000000BA27E15646C451C0AD411620242F4540D189648946C451C05528FC6A242F4540
349	54	32	\N	\N	0102000020E610000002000000D189648946C451C05528FC6A242F4540CC145F9946C451C04560AD82242F4540
350	54	35	\N	\N	0102000020E610000002000000CC145F9946C451C04560AD82242F454093B7E29C46C451C0BB4DE387242F4540
351	54	36	\N	\N	0102000020E61000000200000093B7E29C46C451C0BB4DE387242F45407ABBF6A346C451C0DF0D6292242F4540
352	54	38	\N	\N	0102000020E6100000020000007ABBF6A346C451C0DF0D6292242F4540753910B546C451C088BEBCAB242F4540
353	55	3	\N	\N	0102000020E610000002000000753910B546C451C088BEBCAB242F4540D16AB2FE46C451C04D6CB9AB242F4540
354	55	6	\N	\N	0102000020E610000002000000D16AB2FE46C451C04D6CB9AB242F4540C720D48E47C451C00AECB2AB242F4540
355	56	4	\N	\N	0102000020E610000002000000C720D48E47C451C00AECB2AB242F45405857DA8E47C451C0C2EBB2AB242F4540
356	56	5	\N	\N	0102000020E6100000020000005857DA8E47C451C0C2EBB2AB242F4540C3F7DA8E47C451C0BBEBB2AB242F4540
357	56	7	\N	\N	0102000020E610000002000000C3F7DA8E47C451C0BBEBB2AB242F4540458CE18E47C451C06EEBB2AB242F4540
358	56	8	\N	\N	0102000020E610000003000000458CE18E47C451C06EEBB2AB242F45404AEC279A48C451C098CBA6AB242F4540CEB77BA549C451C0AD979AAB242F4540
359	57	15	\N	\N	0102000020E610000002000000DA1871D44BC451C01B6A6391272F4540A33171D44BC451C091A5FA95272F4540
360	57	18	\N	\N	0102000020E610000003000000A33171D44BC451C091A5FA95272F4540CD7B77D44BC451C01D7F37C0282F4540D63978D44BC451C02D746AE3282F4540
361	57	22	\N	\N	0102000020E610000002000000D63978D44BC451C02D746AE3282F45403BB21AC04BC451C04B79A001292F4540
362	57	30	\N	\N	0102000020E6100000020000003BB21AC04BC451C04B79A001292F45408EDB21C04BC451C0B9815B552A2F4540
363	58	19	\N	\N	0102000020E610000002000000E8A96FD44BC451C096FE6B4D272F4540832870D44BC451C0724BDF64272F4540
364	58	22	\N	\N	0102000020E610000002000000832870D44BC451C0724BDF64272F454029EF70D44BC451C0DE98AA89272F4540
365	58	24	\N	\N	0102000020E61000000200000029EF70D44BC451C0DE98AA89272F454093EF70D44BC451C0BE26BE89272F4540
366	58	26	\N	\N	0102000020E61000000200000093EF70D44BC451C0BE26BE89272F4540F6EF70D44BC451C01B8BD089272F4540
367	58	28	\N	\N	0102000020E610000002000000F6EF70D44BC451C01B8BD089272F454058F070D44BC451C0D49CE289272F4540
368	58	30	\N	\N	0102000020E61000000200000058F070D44BC451C0D49CE289272F45405BF070D44BC451C0D728E389272F4540
369	58	32	\N	\N	0102000020E6100000020000005BF070D44BC451C0D728E389272F4540881771D44BC451C056C82491272F4540
370	58	34	\N	\N	0102000020E610000002000000881771D44BC451C056C82491272F4540F61771D44BC451C08A403991272F4540
371	58	36	\N	\N	0102000020E610000002000000F61771D44BC451C08A403991272F4540671871D44BC451C066064E91272F4540
372	58	38	\N	\N	0102000020E610000002000000671871D44BC451C066064E91272F4540DA1871D44BC451C01B6A6391272F4540
373	59	35	\N	\N	0102000020E610000002000000CEB77BA549C451C0AD979AAB242F45407A0282A549C451C063979AAB242F4540
374	59	36	\N	\N	0102000020E6100000020000007A0282A549C451C063979AAB242F4540E9A482A549C451C05C979AAB242F4540
375	59	38	\N	\N	0102000020E610000002000000E9A482A549C451C05C979AAB242F4540BFD124424AC451C0916593AB242F4540
376	59	39	\N	\N	0102000020E610000003000000BFD124424AC451C0916593AB242F45405183CFB04AC451C047508EAB242F45403585E6F14AC451C0F74F8BAB242F4540
377	59	44	\N	\N	0102000020E6100000020000003585E6F14AC451C0F74F8BAB242F45408DEDF81A4BC451C0D25871E8242F4540
378	59	47	\N	\N	0102000020E6100000020000008DEDF81A4BC451C0D25871E8242F4540ED8868D44BC451C056F464FB252F4540
379	59	61	\N	\N	0102000020E610000003000000ED8868D44BC451C056F464FB252F4540F64669D44BC451C070E9971E262F454037806FD44BC451C05B2DB345272F4540
380	59	63	\N	\N	0102000020E61000000200000037806FD44BC451C05B2DB345272F4540A1806FD44BC451C03BBBC645272F4540
381	59	65	\N	\N	0102000020E610000002000000A1806FD44BC451C03BBBC645272F454004816FD44BC451C0971FD945272F4540
382	59	67	\N	\N	0102000020E61000000200000004816FD44BC451C0971FD945272F454060816FD44BC451C0E416EA45272F4540
383	59	69	\N	\N	0102000020E61000000200000060816FD44BC451C0E416EA45272F454071816FD44BC451C06746ED45272F4540
384	59	70	\N	\N	0102000020E61000000200000071816FD44BC451C06746ED45272F4540E8A96FD44BC451C096FE6B4D272F4540
385	60	7	\N	\N	0102000020E610000002000000CC298BA549C451C02D2C7D91272F45403B2A8BA549C451C01DF59191272F4540
386	60	9	\N	\N	0102000020E6100000040000003B2A8BA549C451C01DF59191272F4540C77791A549C451C0304151C0282F4540BDB592A549C451C00E14FAFB282F454092BD99A549C451C0032EAD4D2A2F4540
387	60	10	\N	\N	0102000020E61000000200000092BD99A549C451C0032EAD4D2A2F4540BADC99A549C451C019C585532A2F4540
388	60	11	\N	\N	0102000020E610000002000000BADC99A549C451C019C585532A2F454099DD99A549C451C0EA9FAF532A2F4540
389	60	12	\N	\N	0102000020E61000000200000099DD99A549C451C0EA9FAF532A2F454071E799A549C451C0855A88552A2F4540
390	60	13	\N	\N	0102000020E61000000200000071E799A549C451C0855A88552A2F45403B059AA549C451C0B6551F5B2A2F4540
391	60	14	\N	\N	0102000020E6100000020000003B059AA549C451C0B6551F5B2A2F4540A7059AA549C451C08587335B2A2F4540
392	61	15	\N	\N	0102000020E61000000200000090BF89A549C451C0A9C0854D272F4540FFBF89A549C451C068899A4D272F4540
393	61	17	\N	\N	0102000020E610000002000000FFBF89A549C451C068899A4D272F4540033D8AA549C451C072950F65272F4540
394	61	20	\N	\N	0102000020E610000002000000033D8AA549C451C072950F65272F454005018BA549C451C01866D689272F4540
395	61	22	\N	\N	0102000020E61000000200000005018BA549C451C01866D689272F45406A018BA549C451C0FE58E989272F4540
396	61	24	\N	\N	0102000020E6100000020000006A018BA549C451C0FE58E989272F4540C8018BA549C451C02029FB89272F4540
397	61	26	\N	\N	0102000020E610000002000000C8018BA549C451C02029FB89272F4540F6288BA549C451C056125591272F4540
398	61	28	\N	\N	0102000020E610000002000000F6288BA549C451C056125591272F454060298BA549C451C08CFA6891272F4540
399	61	30	\N	\N	0102000020E61000000200000060298BA549C451C08CFA6891272F4540CC298BA549C451C02D2C7D91272F4540
400	62	20	\N	\N	0102000020E610000002000000CEB77BA549C451C0AD979AAB242F45401ED67BA549C451C0DAA44AB1242F4540
401	62	23	\N	\N	0102000020E6100000020000001ED67BA549C451C0DAA44AB1242F45407DD67BA549C451C015755CB1242F4540
402	62	26	\N	\N	0102000020E6100000020000007DD67BA549C451C015755CB1242F4540A4D67BA549C451C001AA63B1242F4540
403	62	27	\N	\N	0102000020E610000003000000A4D67BA549C451C001AA63B1242F4540967183A549C451C07EABB11E262F4540C1D686A549C451C01377C6C1262F4540
404	62	28	\N	\N	0102000020E610000002000000C1D686A549C451C01377C6C1262F4540C89689A549C451C071FBDE45272F4540
405	62	30	\N	\N	0102000020E610000002000000C89689A549C451C071FBDE45272F45402D9789A549C451C07FEEF145272F4540
406	62	32	\N	\N	0102000020E6100000020000002D9789A549C451C07FEEF145272F45408C9789A549C451C0C5BE0346272F4540
407	62	34	\N	\N	0102000020E6100000020000008C9789A549C451C0C5BE0346272F4540B7BE89A549C451C094085D4D272F4540
408	62	36	\N	\N	0102000020E610000002000000B7BE89A549C451C094085D4D272F4540BDBE89A549C451C028335E4D272F4540
409	62	38	\N	\N	0102000020E610000002000000BDBE89A549C451C028335E4D272F454024BF89A549C451C0E28E714D272F4540
410	62	40	\N	\N	0102000020E61000000200000024BF89A549C451C0E28E714D272F454090BF89A549C451C0A9C0854D272F4540
411	63	7	\N	\N	0102000020E6100000020000009F61E38E47C451C08D809591272F45400662E38E47C451C0A524A991272F4540
412	63	9	\N	\N	0102000020E6100000020000000662E38E47C451C0A524A991272F45407162E38E47C451C07159BD91272F4540
413	63	11	\N	\N	0102000020E6100000040000007162E38E47C451C07159BD91272F4540899BE98E47C451C0919569C0282F45408DD5EA8E47C451C0706812FC282F454059C7F18E47C451C060EED54D2A2F4540
414	63	12	\N	\N	0102000020E61000000200000059C7F18E47C451C060EED54D2A2F45401BE6F18E47C451C0B9F6AD532A2F4540
415	63	13	\N	\N	0102000020E6100000020000001BE6F18E47C451C0B9F6AD532A2F4540C0F0F18E47C451C04CC4B3552A2F4540
416	63	14	\N	\N	0102000020E610000002000000C0F0F18E47C451C04CC4B3552A2F4540320EF28E47C451C0E6DB4B5B2A2F4540
417	64	13	\N	\N	0102000020E610000002000000E2FBE18E47C451C009159E4D272F454049FCE18E47C451C030B9B14D272F4540
418	64	15	\N	\N	0102000020E61000000200000049FCE18E47C451C030B9B14D272F4540B4FCE18E47C451C00CEEC54D272F4540
419	64	17	\N	\N	0102000020E610000002000000B4FCE18E47C451C00CEEC54D272F45403478E28E47C451C0DFA43C65272F4540
420	64	20	\N	\N	0102000020E6100000020000003478E28E47C451C0DFA43C65272F4540B039E38E47C451C0242DFF89272F4540
421	64	22	\N	\N	0102000020E610000002000000B039E38E47C451C0242DFF89272F4540103AE38E47C451C0208C118A272F4540
422	64	24	\N	\N	0102000020E610000002000000103AE38E47C451C0208C118A272F45403961E38E47C451C0C3218291272F4540
423	64	26	\N	\N	0102000020E6100000020000003961E38E47C451C0C3218291272F45409F61E38E47C451C08D809591272F4540
424	65	15	\N	\N	0102000020E610000002000000C720D48E47C451C00AECB2AB242F45402E21D48E47C451C01490C6AB242F4540
425	65	17	\N	\N	0102000020E6100000020000002E21D48E47C451C01490C6AB242F45400A3FD48E47C451C060D672B1242F4540
426	65	20	\N	\N	0102000020E6100000020000000A3FD48E47C451C060D672B1242F4540653FD48E47C451C0EB1884B1242F4540
427	65	21	\N	\N	0102000020E610000003000000653FD48E47C451C0EB1884B1242F4540F9C1DB8E47C451C0DEFFC91E262F4540C41CDF8E47C451C0BCB0F3C1262F4540
428	65	22	\N	\N	0102000020E610000002000000C41CDF8E47C451C0BCB0F3C1262F4540F3D3E18E47C451C005C10746272F4540
429	65	24	\N	\N	0102000020E610000002000000F3D3E18E47C451C005C10746272F454053D4E18E47C451C0EA1F1A46272F4540
430	65	26	\N	\N	0102000020E61000000200000053D4E18E47C451C0EA1F1A46272F454079FBE18E47C451C09E1C8A4D272F4540
431	65	28	\N	\N	0102000020E61000000200000079FBE18E47C451C09E1C8A4D272F45407FFBE18E47C451C0313F8B4D272F4540
432	65	30	\N	\N	0102000020E6100000020000007FFBE18E47C451C0313F8B4D272F4540E2FBE18E47C451C009159E4D272F4540
433	66	23	\N	\N	0102000020E610000002000000562DC49545C451C0BBC9B44D272F4540B52DC49545C451C0C61FC74D272F4540
434	66	25	\N	\N	0102000020E610000002000000B52DC49545C451C0C61FC74D272F4540192EC49545C451C0913CDA4D272F4540
435	66	27	\N	\N	0102000020E610000002000000192EC49545C451C0913CDA4D272F45407F2EC49545C451C0EDE3ED4D272F4540
436	66	29	\N	\N	0102000020E6100000020000007F2EC49545C451C0EDE3ED4D272F4540CB3AC49545C451C099444B50272F4540
437	66	46	\N	\N	0102000020E610000002000000CB3AC49545C451C099444B50272F45401249898745C451C0215B6765272F4540
438	67	11	\N	\N	0102000020E610000002000000753910B546C451C088BEBCAB242F454046A55BA046C451C0DBDA73CA242F4540
439	67	13	\N	\N	0102000020E61000000200000046A55BA046C451C0DBDA73CA242F454011E1199046C451C0F39991E2242F4540
440	67	15	\N	\N	0102000020E61000000300000011E1199046C451C0F39991E2242F4540B5D5818346C451C0374A40F5242F45404A9FA9EE45C451C044AE0DD2252F4540
441	67	18	\N	\N	0102000020E6100000020000004A9FA9EE45C451C044AE0DD2252F454052A032A145C451C057D0F744262F4540
442	67	19	\N	\N	0102000020E61000000400000052A032A145C451C057D0F744262F454034CC34A145C451C0AA7AD2AF262F45408F50C19545C451C0B528CFC0262F45405957C19545C451C062661DC2262F4540
443	67	20	\N	\N	0102000020E6100000020000005957C19545C451C062661DC2262F4540502DC49545C451C0B9AEB34D272F4540
444	67	22	\N	\N	0102000020E610000002000000502DC49545C451C0B9AEB34D272F4540562DC49545C451C0BBC9B44D272F4540
445	68	10	\N	\N	0102000020E6100000020000003E2F8A8745C451C006D8AC91272F4540A02F8A8745C451C017B1BF91272F4540
446	68	12	\N	\N	0102000020E610000002000000A02F8A8745C451C017B1BF91272F454003308A8745C451C095CBD291272F4540
447	68	14	\N	\N	0102000020E61000000200000003308A8745C451C095CBD291272F454069308A8745C451C08A70E691272F4540
448	68	16	\N	\N	0102000020E61000000300000069308A8745C451C08A70E691272F4540AC55908745C451C00BED80C0282F4540D115918745C451C0282276E5282F4540
449	68	18	\N	\N	0102000020E610000003000000D115918745C451C0282276E5282F454028761C7C45C451C0058074F6282F4540C6B5237C45C451C0B8F7765B2A2F4540
450	68	19	\N	\N	0102000020E610000002000000C6B5237C45C451C0B8F7765B2A2F45402AB6237C45C451C0340F8A5B2A2F4540
451	68	20	\N	\N	0102000020E6100000020000002AB6237C45C451C0340F8A5B2A2F454010D3237C45C451C0437919612A2F4540
452	69	2	\N	\N	0102000020E6100000020000001249898745C451C0215B6765272F45401B088A8745C451C0F3B8258A272F4540
453	69	4	\N	\N	0102000020E6100000020000001B088A8745C451C0F3B8258A272F45403E2F8A8745C451C006D8AC91272F4540
454	70	7	\N	\N	0102000020E6100000020000001ABE8E7745C451C02923B64D272F4540FEF4701945C451C0624229C2262F4540
455	70	14	\N	\N	0102000020E610000002000000FEF4701945C451C0624229C2262F45403BA49BE944C451C099632BC2262F4540
456	72	8	\N	\N	0102000020E61000000200000038F0CA2346C451C0544B82C21F2F4540B5C636E145C451C047604625202F4540
457	72	11	\N	\N	0102000020E610000002000000B5C636E145C451C047604625202F4540787EC3E045C451C01264F125202F4540
458	72	13	\N	\N	0102000020E610000002000000787EC3E045C451C01264F125202F45403653FADD45C451C08A56132A202F4540
459	72	14	\N	\N	0102000020E6100000020000003653FADD45C451C08A56132A202F4540B3246B8E45C451C002F018A0202F4540
460	72	16	\N	\N	0102000020E610000002000000B3246B8E45C451C002F018A0202F4540D76D2A6B45C451C0799B64D4202F4540
461	73	7	\N	\N	0102000020E610000002000000F7B6E77B42C451C02C23C2851C2F45403FB7E77B42C451C0A04CD0851C2F4540
462	73	8	\N	\N	0102000020E6100000020000003FB7E77B42C451C0A04CD0851C2F454056B7E77B42C451C040D1D4851C2F4540
463	73	10	\N	\N	0102000020E61000000200000056B7E77B42C451C040D1D4851C2F45406661EE7B42C451C09AAC31D41D2F4540
464	73	13	\N	\N	0102000020E6100000020000006661EE7B42C451C09AAC31D41D2F4540F861EE7B42C451C000424ED41D2F4540
465	73	14	\N	\N	0102000020E610000002000000F861EE7B42C451C000424ED41D2F4540B3DDF17B42C451C0306512831E2F4540
466	74	12	\N	\N	0102000020E610000003000000C022765D4EC451C000B91D9A0B2F454023266D5D4EC451C0C5F43BF6092F454012706C5D4EC451C0599201D5092F4540
467	74	15	\N	\N	0102000020E61000000200000012706C5D4EC451C0599201D5092F45405FA167BF50C451C021E41B4C062F4540
468	74	24	\N	\N	0102000020E6100000020000005FA167BF50C451C021E41B4C062F4540E8E34CBF50C451C0531ABE7B012F4540
469	76	1	\N	\N	0102000020E6100000020000001F669C5D4EC451C07C0AD895122F4540C2A28E5D4EC451C02404CE12102F4540
470	76	2	\N	\N	0102000020E610000003000000C2A28E5D4EC451C02404CE12102F454025DB7F5D4EC451C032AC44600D2F454086DE765D4EC451C03AE862BC0B2F4540
471	77	14	\N	\N	0102000020E610000002000000E8E34CBF50C451C0531ABE7B012F45401FE34CBF50C451C073E3997B012F4540
472	77	15	\N	\N	0102000020E6100000020000001FE34CBF50C451C073E3997B012F454002E34CBF50C451C061C8947B012F4540
473	77	17	\N	\N	0102000020E61000000200000002E34CBF50C451C061C8947B012F4540BCF447BF50C451C088025698002F4540
474	77	18	\N	\N	0102000020E610000002000000BCF447BF50C451C088025698002F454002E347BF50C451C0C6222595002F4540
475	77	21	\N	\N	0102000020E61000000200000002E347BF50C451C0C6222595002F45400D6041BF50C451C080BA0B69FF2E4540
476	77	22	\N	\N	0102000020E6100000020000000D6041BF50C451C080BA0B69FF2E4540FD9936BF50C451C0498C8478FD2E4540
477	77	25	\N	\N	0102000020E610000002000000FD9936BF50C451C0498C8478FD2E45403E6D2DBF50C451C01D79ADD1FB2E4540
478	77	27	\N	\N	0102000020E6100000020000003E6D2DBF50C451C01D79ADD1FB2E4540236D2DBF50C451C0FDA1A8D1FB2E4540
479	77	28	\N	\N	0102000020E610000002000000236D2DBF50C451C0FDA1A8D1FB2E45405F6C2DBF50C451C0914F85D1FB2E4540
480	78	2	\N	\N	0102000020E6100000020000005F6C2DBF50C451C0914F85D1FB2E4540AFE123BF50C451C0B8EBC319FA2E4540
481	78	3	\N	\N	0102000020E610000002000000AFE123BF50C451C0B8EBC319FA2E4540187823BF50C451C04A8DC106FA2E4540
482	78	4	\N	\N	0102000020E610000002000000187823BF50C451C04A8DC106FA2E4540E62011BF50C451C0AAEB7BB9F62E4540
483	79	6	\N	\N	0102000020E610000007000000B9DF2EAC4CC451C06B51B785F52E4540922700E04BC451C058D0C085F52E45405DAD3AB54BC451C021CCC285F52E454047437EA34AC451C06ED8DFEFF32E4540FB7D40244AC451C09AB2E5EFF32E4540215F5B1B4AC451C0E440B5E2F32E45408C90CAC348C451C092E3C4E2F32E4540
484	79	9	\N	\N	0102000020E6100000040000008C90CAC348C451C092E3C4E2F32E45400B33A81F47C451C04F02D8E2F32E4540E7B46A1547C451C01DF108F2F32E4540ECA17EA046C451C0C9340EF2F32E4540
485	79	12	\N	\N	0102000020E610000002000000ECA17EA046C451C0C9340EF2F32E454052001F9646C451C05AAC0EF2F32E4540
486	80	2	\N	\N	0102000020E610000002000000AB9A7A2B4DC451C02160B185F52E4540A7084CAC4CC451C00F50B785F52E4540
487	80	4	\N	\N	0102000020E610000002000000A7084CAC4CC451C00F50B785F52E4540B9DF2EAC4CC451C06B51B785F52E4540
488	81	2	\N	\N	0102000020E610000004000000E62011BF50C451C0AAEB7BB9F62E454012F865EF4FC451C05B039085F52E4540D152A9F74DC451C0C4CEA785F52E454059D1972B4DC451C0C35EB185F52E4540
489	81	4	\N	\N	0102000020E61000000200000059D1972B4DC451C0C35EB185F52E4540AB9A7A2B4DC451C02160B185F52E4540
490	82	7	\N	\N	0102000020E6100000020000003AB0E6D154C451C04D1E7CA3F52E45403674F6D154C451C0871D7CA3F52E4540
491	82	9	\N	\N	0102000020E6100000030000003674F6D154C451C0871D7CA3F52E45401F69159E55C451C0F71F72A3F52E45400B1CDCC055C451C0186B70A3F52E4540
492	82	14	\N	\N	0102000020E6100000020000000B1CDCC055C451C0186B70A3F52E4540C31652E356C451C03F7589F4F32E4540
493	83	2	\N	\N	0102000020E610000002000000D2F49A5254C451C08A5382A3F52E4540A9B1AA5254C451C0C65282A3F52E4540
494	83	4	\N	\N	0102000020E610000002000000A9B1AA5254C451C0C65282A3F52E45403AB0E6D154C451C04D1E7CA3F52E4540
495	85	5	\N	\N	0102000020E610000004000000C31652E356C451C03F7589F4F32E45405BE30F6257C451C0453083F4F32E45402F3CE46557C451C040D4D4EEF32E4540FFC2047158C451C0B67CC7EEF32E4540
496	85	8	\N	\N	0102000020E610000002000000FFC2047158C451C0B67CC7EEF32E4540FD3155DF58C451C036FAC1EEF32E4540
497	85	9	\N	\N	0102000020E610000002000000FD3155DF58C451C036FAC1EEF32E454001ABCEFB58C451C0218EC0EEF32E4540
498	85	10	\N	\N	0102000020E61000000400000001ABCEFB58C451C0218EC0EEF32E4540725C73645AC451C0DF8AAEEEF32E4540164479695AC451C0B03221F6F32E4540B9F8C4E85AC451C062C71AF6F32E4540
499	86	6	\N	\N	0102000020E610000002000000C31652E356C451C03F7589F4F32E454013C84D2956C451C081B2B8E0F22E4540
500	86	9	\N	\N	0102000020E61000000200000013C84D2956C451C081B2B8E0F22E454043F1C3F455C451C0DA04D292F22E4540
501	86	10	\N	\N	0102000020E61000000200000043F1C3F455C451C0DA04D292F22E4540DD1AA0A255C451C0731A0719F22E4540
502	86	12	\N	\N	0102000020E610000002000000DD1AA0A255C451C0731A0719F22E4540F689522E55C451C03081946CF12E4540
503	87	17	\N	\N	0102000020E6100000030000002FCF09D254C451C008F652D1FB2E454018B0389E55C451C0ADF748D1FB2E4540B7A8B7B955C451C04A9E47D1FB2E4540
504	87	20	\N	\N	0102000020E610000002000000B7A8B7B955C451C04A9E47D1FB2E4540A21F9D9E56C451C06DDBB57DFA2E4540
505	87	22	\N	\N	0102000020E610000002000000A21F9D9E56C451C06DDBB57DFA2E4540A84717A956C451C0DEDB2A6EFA2E4540
506	87	23	\N	\N	0102000020E610000002000000A84717A956C451C0DEDB2A6EFA2E454028C566E356C451C0E6F2276EFA2E4540
507	87	26	\N	\N	0102000020E61000000200000028C566E356C451C0E6F2276EFA2E4540DFFA69DF58C451C094980E6EFA2E4540
508	87	27	\N	\N	0102000020E610000002000000DFFA69DF58C451C094980E6EFA2E4540DD23CAD55AC451C04786F56DFA2E4540
509	87	33	\N	\N	0102000020E610000002000000DD23CAD55AC451C04786F56DFA2E4540312A270F5BC451C0CE06DC18FA2E4540
510	87	34	\N	\N	0102000020E610000002000000312A270F5BC451C0CE06DC18FA2E454086C8765B5BC451C0C32AD818FA2E4540
511	88	2	\N	\N	0102000020E610000002000000D2FABD5254C451C0452B59D1FB2E45405FF9F9D154C451C0CEF652D1FB2E4540
512	88	4	\N	\N	0102000020E6100000020000005FF9F9D154C451C0CEF652D1FB2E45402FCF09D254C451C008F652D1FB2E4540
513	89	8	\N	\N	0102000020E6100000020000005F6C2DBF50C451C0914F85D1FB2E45402D733BBF50C451C0E44E85D1FB2E4540
514	89	10	\N	\N	0102000020E6100000020000002D733BBF50C451C0E44E85D1FB2E454056FEC4CB50C451C080B484D1FB2E4540
515	89	11	\N	\N	0102000020E61000000200000056FEC4CB50C451C080B484D1FB2E4540ADBBB7DF51C451C04E6E77D1FB2E4540
516	89	14	\N	\N	0102000020E610000003000000ADBBB7DF51C451C04E6E77D1FB2E4540E8198F8653C451C02E1763D1FB2E4540182CAE5254C451C00A2C59D1FB2E4540
517	89	16	\N	\N	0102000020E610000002000000182CAE5254C451C00A2C59D1FB2E4540D2FABD5254C451C0452B59D1FB2E4540
518	90	13	\N	\N	0102000020E610000003000000A8C56FAC4CC451C0864BEF7B012F45408A3D54914BC451C01073FC7B012F45401F0261784BC451C0CD9AFD7B012F4540
519	90	22	\N	\N	0102000020E6100000020000001F0261784BC451C0CD9AFD7B012F454063129FB449C451C0836824DEFE2E4540
520	90	24	\N	\N	0102000020E61000000200000063129FB449C451C0836824DEFE2E454078557B6249C451C04B4D5964FE2E4540
521	90	26	\N	\N	0102000020E61000000200000078557B6249C451C04B4D5964FE2E45405C7DE6C348C451C02EE43579FD2E4540
522	91	2	\N	\N	0102000020E610000002000000E7B0BB2B4DC451C0395AE97B012F4540B0579E2B4DC451C0985BE97B012F4540
523	91	4	\N	\N	0102000020E610000002000000B0579E2B4DC451C0985BE97B012F4540A8C56FAC4CC451C0864BEF7B012F4540
524	92	11	\N	\N	0102000020E610000002000000E8E34CBF50C451C0531ABE7B012F4540B89A3EBF50C451C0001BBE7B012F4540
525	92	13	\N	\N	0102000020E610000002000000B89A3EBF50C451C0001BBE7B012F45403CC231BF50C451C09C1BBE7B012F4540
526	92	16	\N	\N	0102000020E6100000020000003CC231BF50C451C09C1BBE7B012F45403688685D4EC451C03D01DB7B012F4540
527	92	19	\N	\N	0102000020E6100000020000003688685D4EC451C03D01DB7B012F4540A3C6575D4EC451C00902DB7B012F4540
528	92	21	\N	\N	0102000020E610000002000000A3C6575D4EC451C00902DB7B012F4540CD72575D4EC451C00D02DB7B012F4540
529	92	22	\N	\N	0102000020E610000003000000CD72575D4EC451C00D02DB7B012F45400339D7464EC451C00513DC7B012F4540E7B0BB2B4DC451C0395AE97B012F4540
530	93	18	\N	\N	0102000020E6100000020000005C7DE6C348C451C02EE43579FD2E45400840E6C348C451C0247EA46DFD2E4540
531	93	31	\N	\N	0102000020E6100000020000000840E6C348C451C0247EA46DFD2E4540C1C51E2448C451C0D516BA80FC2E4540
532	93	33	\N	\N	0102000020E610000002000000C1C51E2448C451C0D516BA80FC2E45400190EB7247C451C0F2EEFA79FB2E4540
533	93	34	\N	\N	0102000020E6100000020000000190EB7247C451C0F2EEFA79FB2E4540495EFF2E47C451C09C424415FB2E4540
534	93	35	\N	\N	0102000020E610000002000000495EFF2E47C451C09C424415FB2E45409ED32B7946C451C0A103A907FA2E4540
535	93	36	\N	\N	0102000020E6100000020000009ED32B7946C451C0A103A907FA2E45404415BA2C46C451C00372AC07FA2E4540
536	94	8	\N	\N	0102000020E6100000020000005C7DE6C348C451C02EE43579FD2E4540F9F7BF5347C451C0B51C5A9BFF2E4540
537	94	11	\N	\N	0102000020E610000002000000F9F7BF5347C451C0B51C5A9BFF2E4540F16DC6AA46C451C0F6860596002F4540
538	94	16	\N	\N	0102000020E610000002000000F16DC6AA46C451C0F6860596002F45408A0EA3A046C451C0AFFB0596002F4540
539	95	1	\N	\N	0102000020E6100000020000008A0EA3A046C451C0AFFB0596002F4540F43CCE6845C451C0257E9D64022F4540
540	95	2	\N	\N	0102000020E610000003000000F43CCE6845C451C0257E9D64022F45408785761C45C451C0B0E5A064022F454036C6CD9B44C451C0A6667D23032F4540
541	96	2	\N	\N	0102000020E6100000020000008A0EA3A046C451C0AFFB0596002F45404BA64CD645C451C0BDEC006AFF2E4540
542	96	4	\N	\N	0102000020E6100000020000004BA64CD645C451C0BDEC006AFF2E4540EA39FE9345C451C0C8E3036AFF2E4540
543	97	17	\N	\N	0102000020E610000002000000B1EE667158C451C059F2E8A4122F45408BE732FC58C451C0526A01D7112F4540
544	97	32	\N	\N	0102000020E6100000020000008BE732FC58C451C0526A01D7112F4540D64D31FC58C451C0B1CD8F90112F4540
545	97	34	\N	\N	0102000020E610000002000000D64D31FC58C451C0B1CD8F90112F4540379C28FC58C451C0B344E511102F4540
546	98	33	\N	\N	0102000020E6100000020000004EE5007B5DC451C04E1199BD152F4540D64964EE5DC451C0932AAF68162F4540
547	98	34	\N	\N	0102000020E610000002000000D64964EE5DC451C0932AAF68162F4540D108CCC55EC451C019E010A8172F4540
548	98	48	\N	\N	0102000020E610000002000000D108CCC55EC451C019E010A8172F45400C9EE3C55EC451C0AB8051961B2F4540
549	98	59	\N	\N	0102000020E6100000020000000C9EE3C55EC451C0AB8051961B2F45406F20E0155FC451C0C1F0E90C1C2F4540
550	98	66	\N	\N	0102000020E6100000020000006F20E0155FC451C0C1F0E90C1C2F45402901E3155FC451C0681981871C2F4540
551	99	4	\N	\N	0102000020E6100000020000002901E3155FC451C0681981871C2F454022FBEA155FC451C0645749DB1D2F4540
552	99	5	\N	\N	0102000020E61000000200000022FBEA155FC451C0645749DB1D2F4540F9FBEA155FC451C061276DDB1D2F4540
553	99	8	\N	\N	0102000020E610000002000000F9FBEA155FC451C061276DDB1D2F45409986EE155FC451C030A649721E2F4540
554	100	10	\N	\N	0102000020E61000000200000029F785FA5CC451C007CB9C871C2F4540BEB7BECC5CC451C0F61F9F871C2F4540
555	100	11	\N	\N	0102000020E610000004000000BEB7BECC5CC451C0F61F9F871C2F454056D6F1145CC451C0A87CA8871C2F4540175C25BC5BC451C002250A041C2F454095A11BBC5BC451C080250A041C2F4540
556	100	17	\N	\N	0102000020E61000000200000095A11BBC5BC451C080250A041C2F45403157A1FE5AC451C070E5201D1D2F4540
557	100	18	\N	\N	0102000020E6100000020000003157A1FE5AC451C070E5201D1D2F4540153143835AC451C035CC24D41D2F4540
558	100	20	\N	\N	0102000020E610000002000000153143835AC451C035CC24D41D2F45409307107E5AC451C04E91DBDB1D2F4540
559	101	3	\N	\N	0102000020E610000002000000914C887E5DC451C02C0B96871C2F4540661C177B5DC451C03A3896871C2F4540
560	101	6	\N	\N	0102000020E610000002000000661C177B5DC451C03A3896871C2F454029F785FA5CC451C007CB9C871C2F4540
561	103	21	\N	\N	0102000020E6100000020000009307107E5AC451C04E91DBDB1D2F4540CAE3F3ED5AC451C005E4C1811E2F4540
562	103	22	\N	\N	0102000020E610000002000000CAE3F3ED5AC451C005E4C1811E2F4540570443635BC451C0341EB12F1F2F4540
563	103	42	\N	\N	0102000020E610000002000000570443635BC451C0341EB12F1F2F4540B0EB48635BC451C07C172F30202F4540
564	104	15	\N	\N	0102000020E610000002000000B0EB48635BC451C07C172F30202F454061880D8A5BC451C08E4FAA69202F4540
565	104	17	\N	\N	0102000020E61000000200000061880D8A5BC451C08E4FAA69202F4540F66C4E8F5BC451C00E627471202F4540
566	104	20	\N	\N	0102000020E610000002000000F66C4E8F5BC451C00E627471202F4540419D608F5BC451C0F0598F71202F4540
567	104	21	\N	\N	0102000020E610000003000000419D608F5BC451C0F0598F71202F454012E32FCE5BC451C06915B0CE202F454081743CDF5BC451C0DD6AF7E7202F4540
568	104	23	\N	\N	0102000020E61000000200000081743CDF5BC451C0DD6AF7E7202F4540E288951C5CC451C0574CED42212F4540
569	104	25	\N	\N	0102000020E610000002000000E288951C5CC451C0574CED42212F45407673602D5CC451C0514AD35B212F4540
570	104	27	\N	\N	0102000020E6100000020000007673602D5CC451C0514AD35B212F45403383A33D5CC451C0CAD9EF73212F4540
571	104	29	\N	\N	0102000020E6100000020000003383A33D5CC451C0CAD9EF73212F454013727F625CC451C0F97B96AA212F4540
572	104	30	\N	\N	0102000020E61000000200000013727F625CC451C0F97B96AA212F45405278D1CC5CC451C014943A48222F4540
573	105	20	\N	\N	0102000020E610000002000000B0EB48635BC451C07C172F30202F4540A8B4155E5BC451C0EEEFE537202F4540
574	105	22	\N	\N	0102000020E610000002000000A8B4155E5BC451C0EEEFE537202F454048D268305BC451C0FB39A87B202F4540
575	105	28	\N	\N	0102000020E61000000200000048D268305BC451C0FB39A87B202F454064A17D305BC451C086C8B004242F4540
576	105	29	\N	\N	0102000020E61000000200000064A17D305BC451C086C8B004242F454051887E305BC451C0163BEC2B242F4540
577	105	30	\N	\N	0102000020E61000000200000051887E305BC451C0163BEC2B242F45405E33E12C5BC451C0F3F24831242F4540
578	105	32	\N	\N	0102000020E6100000020000005E33E12C5BC451C0F3F24831242F4540A3E70EFF5AC451C03DB24275242F4540
579	105	34	\N	\N	0102000020E610000002000000A3E70EFF5AC451C03DB24275242F45403BD0E7F65AC451C0CBDE5A81242F4540
580	105	37	\N	\N	0102000020E6100000020000003BD0E7F65AC451C0CBDE5A81242F4540EBA489F45AC451C05D1DDE84242F4540
581	105	39	\N	\N	0102000020E610000002000000EBA489F45AC451C05D1DDE84242F4540A4C396EF5AC451C0ED83358C242F4540
582	105	40	\N	\N	0102000020E610000002000000A4C396EF5AC451C0ED83358C242F454019CF7DD75AC451C05515F5AF242F4540
583	106	7	\N	\N	0102000020E61000000200000019CF7DD75AC451C05515F5AF242F4540C309267E5AC451C02495F9AF242F4540
584	106	10	\N	\N	0102000020E610000002000000C309267E5AC451C02495F9AF242F454044DD9BFC59C451C02B1B00B0242F4540
585	106	11	\N	\N	0102000020E61000000200000044DD9BFC59C451C02B1B00B0242F4540CC8B94FC59C451C08A1B00B0242F4540
586	106	13	\N	\N	0102000020E610000002000000CC8B94FC59C451C08A1B00B0242F454063D993FC59C451C0931B00B0242F4540
587	106	14	\N	\N	0102000020E61000000200000063D993FC59C451C0931B00B0242F454033138DFC59C451C0EA1B00B0242F4540
588	107	9	\N	\N	0102000020E61000000200000033138DFC59C451C0EA1B00B0242F454043B86AFC58C451C006F10CB0242F4540
589	107	10	\N	\N	0102000020E61000000300000043B86AFC58C451C006F10CB0242F4540766241F158C451C02D800DB0242F45401EBEF0DF58C451C0FE5C0EB0242F4540
590	107	11	\N	\N	0102000020E6100000020000001EBEF0DF58C451C0FE5C0EB0242F45409E75A07158C451C0CFDB13B0242F4540
591	107	14	\N	\N	0102000020E6100000020000009E75A07158C451C0CFDB13B0242F45405F18F4E557C451C00CD11AB0242F4540
592	107	15	\N	\N	0102000020E6100000020000005F18F4E557C451C00CD11AB0242F45409ADDECE557C451C068D11AB0242F4540
593	107	17	\N	\N	0102000020E6100000020000009ADDECE557C451C068D11AB0242F4540542DECE557C451C071D11AB0242F4540
594	107	18	\N	\N	0102000020E610000002000000542DECE557C451C071D11AB0242F4540EE7BE5E557C451C0C6D11AB0242F4540
595	108	16	\N	\N	0102000020E6100000020000009AF0F5E557C451C08586B988272F454017F1F5E557C451C09A1DCF88272F4540
596	108	18	\N	\N	0102000020E61000000200000017F1F5E557C451C09A1DCF88272F454092F1F5E557C451C03161E488272F4540
597	108	20	\N	\N	0102000020E61000000200000092F1F5E557C451C03161E488272F454095F1F5E557C451C02D06E588272F4540
598	108	22	\N	\N	0102000020E61000000200000095F1F5E557C451C02D06E588272F45404A1BF6E557C451C0CE9A1B90272F4540
599	108	24	\N	\N	0102000020E6100000020000004A1BF6E557C451C0CE9A1B90272F4540D51BF6E557C451C061933390272F4540
600	108	26	\N	\N	0102000020E610000002000000D51BF6E557C451C061933390272F4540641CF6E557C451C0EC4E4C90272F4540
601	108	28	\N	\N	0102000020E610000002000000641CF6E557C451C0EC4E4C90272F45407F37F6E557C451C03176FC94272F4540
602	108	31	\N	\N	0102000020E6100000040000007F37F6E557C451C03176FC94272F45407AC7FCE557C451C07F9B8DB7282F4540B020FEE557C451C0A07342F3282F4540A2EC05E657C451C05A8C794C2A2F4540
603	108	32	\N	\N	0102000020E610000002000000A2EC05E657C451C05A8C794C2A2F4540850E06E657C451C062F155522A2F4540
604	109	14	\N	\N	0102000020E610000002000000A367F4E557C451C0041BC244272F45402068F4E557C451C019B2D744272F4540
605	109	16	\N	\N	0102000020E6100000020000002068F4E557C451C019B2D744272F45409368F4E557C451C0F2A8EB44272F4540
606	109	18	\N	\N	0102000020E6100000020000009368F4E557C451C0F2A8EB44272F4540A968F4E557C451C0F169EF44272F4540
607	109	20	\N	\N	0102000020E610000002000000A968F4E557C451C0F169EF44272F45405392F4E557C451C0352F244C272F4540
608	109	22	\N	\N	0102000020E6100000020000005392F4E557C451C0352F244C272F4540DE92F4E557C451C0CB273C4C272F4540
609	109	24	\N	\N	0102000020E610000002000000DE92F4E557C451C0CB273C4C272F45406D93F4E557C451C058E3544C272F4540
610	109	26	\N	\N	0102000020E6100000020000006D93F4E557C451C058E3544C272F454016F0F5E557C451C0ACA0A288272F4540
611	109	28	\N	\N	0102000020E61000000200000016F0F5E557C451C0ACA0A288272F45409AF0F5E557C451C08586B988272F4540
612	110	7	\N	\N	0102000020E610000002000000EE7BE5E557C451C0C6D11AB0242F45406B7CE5E557C451C0C86830B0242F4540
613	110	9	\N	\N	0102000020E6100000020000006B7CE5E557C451C0C86830B0242F45409D7CE5E557C451C0992939B0242F4540
614	110	12	\N	\N	0102000020E6100000030000009D7CE5E557C451C0992939B0242F4540C590EDE557C451C0E105EE15262F4540C0E4F1E557C451C089B690D5262F4540
615	110	13	\N	\N	0102000020E610000002000000C0E4F1E557C451C089B690D5262F45401F67F4E557C451C03C35AB44272F4540
616	110	14	\N	\N	0102000020E6100000020000001F67F4E557C451C03C35AB44272F4540A367F4E557C451C0041BC244272F4540
617	111	23	\N	\N	0102000020E61000000200000006FEFAB655C451C03220D588272F454085FEFAB655C451C02E6BEB88272F4540
618	111	25	\N	\N	0102000020E61000000200000085FEFAB655C451C02E6BEB88272F45404928FBB655C451C0AC023B90272F4540
619	111	27	\N	\N	0102000020E6100000020000004928FBB655C451C0AC023B90272F4540CC28FBB655C451C046065290272F4540
620	111	29	\N	\N	0102000020E610000002000000CC28FBB655C451C046065290272F45405229FBB655C451C0BD6A6990272F4540
621	111	31	\N	\N	0102000020E6100000020000005229FBB655C451C0BD6A6990272F4540DC29FBB655C451C0748B8190272F4540
622	111	33	\N	\N	0102000020E610000003000000DC29FBB655C451C0748B8190272F4540EDBF01B755C451C02F35A9B7282F45406D8902B755C451C03E50EFDA282F4540
623	111	37	\N	\N	0102000020E6100000020000006D8902B755C451C03E50EFDA282F4540A86061CB55C451C09C6323F9282F4540
624	111	46	\N	\N	0102000020E610000002000000A86061CB55C451C09C6323F9282F45400EF568CB55C451C0D834AA4C2A2F4540
625	112	21	\N	\N	0102000020E610000002000000C479F9B655C451C0B0B4DD44272F4540437AF9B655C451C0B0FFF344272F4540
626	112	23	\N	\N	0102000020E610000002000000437AF9B655C451C0B0FFF344272F4540BB7AF9B655C451C0A9020945272F4540
627	112	25	\N	\N	0102000020E610000002000000BB7AF9B655C451C0A9020945272F45402A7BF9B655C451C0A86E1C45272F4540
628	112	27	\N	\N	0102000020E6100000020000002A7BF9B655C451C0A86E1C45272F45403F7BF9B655C451C055152045272F4540
629	112	29	\N	\N	0102000020E6100000020000003F7BF9B655C451C055152045272F454003A4F9B655C451C0A6E0424C272F4540
630	112	31	\N	\N	0102000020E61000000200000003A4F9B655C451C0A6E0424C272F45400AA4F9B655C451C07C39444C272F4540
631	112	33	\N	\N	0102000020E6100000020000000AA4F9B655C451C07C39444C272F45408AA4F9B655C451C0AE9A5A4C272F4540
632	112	35	\N	\N	0102000020E6100000020000008AA4F9B655C451C0AE9A5A4C272F454010A5F9B655C451C028FF714C272F4540
633	112	37	\N	\N	0102000020E61000000200000010A5F9B655C451C028FF714C272F45409AA5F9B655C451C0E11F8A4C272F4540
634	112	39	\N	\N	0102000020E6100000020000009AA5F9B655C451C0E11F8A4C272F4540622BFAB655C451C0AE85F563272F4540
635	112	42	\N	\N	0102000020E610000002000000622BFAB655C451C0AE85F563272F454006FEFAB655C451C03220D588272F4540
636	113	22	\N	\N	0102000020E610000002000000EE7BE5E557C451C0C6D11AB0242F4540C5C85E4F57C451C0734622B0242F4540
637	113	23	\N	\N	0102000020E610000003000000C5C85E4F57C451C0734622B0242F4540649589DA56C451C0E50F28B0242F45406707679056C451C079B82BB0242F4540
638	113	29	\N	\N	0102000020E6100000020000006707679056C451C079B82BB0242F45405FEEF1B655C451C07384C3F2252F4540
639	113	43	\N	\N	0102000020E6100000030000005FEEF1B655C451C07384C3F2252F4540DFB7F2B655C451C08D9F0916262F45409A86F6B655C451C05F76ABC0262F4540
640	113	44	\N	\N	0102000020E6100000020000009A86F6B655C451C05F76ABC0262F4540C479F9B655C451C0B0B4DD44272F4540
641	114	13	\N	\N	0102000020E61000000200000024B89DFC59C451C0A6D09E88272F4540A4B89DFC59C451C0C7A1B488272F4540
642	114	15	\N	\N	0102000020E610000002000000A4B89DFC59C451C0C7A1B488272F4540A7B89DFC59C451C0154BB588272F4540
643	114	17	\N	\N	0102000020E610000002000000A7B89DFC59C451C0154BB588272F454046E39DFC59C451C0E8F1FE8F272F4540
644	114	19	\N	\N	0102000020E61000000200000046E39DFC59C451C0E8F1FE8F272F4540DAE39DFC59C451C08F411890272F4540
645	114	21	\N	\N	0102000020E610000002000000DAE39DFC59C451C08F411890272F45405DFF9DFC59C451C0F1B8CC94272F4540
646	114	24	\N	\N	0102000020E6100000040000005DFF9DFC59C451C0F1B8CC94272F454014A3A4FC59C451C09EE572B7282F4540B2FFA5FC59C451C039B30FF3282F45408AE2ADFC59C451C0FB22484C2A2F4540
647	114	25	\N	\N	0102000020E6100000020000008AE2ADFC59C451C0FB22484C2A2F4540D404AEFC59C451C0BB1625522A2F4540
648	114	26	\N	\N	0102000020E610000002000000D404AEFC59C451C0BB1625522A2F4540E205AEFC59C451C0044653522A2F4540
649	115	12	\N	\N	0102000020E610000002000000AD2A9CFC59C451C02365A744272F4540252B9CFC59C451C0BBE0BB44272F4540
650	115	14	\N	\N	0102000020E610000002000000252B9CFC59C451C0BBE0BB44272F45403B2B9CFC59C451C0E2BABF44272F4540
651	115	16	\N	\N	0102000020E6100000020000003B2B9CFC59C451C0E2BABF44272F4540CF559CFC59C451C00187074C272F4540
652	115	18	\N	\N	0102000020E610000002000000CF559CFC59C451C00187074C272F454063569CFC59C451C092D6204C272F4540
653	115	20	\N	\N	0102000020E61000000200000063569CFC59C451C092D6204C272F454019B79DFC59C451C013327188272F4540
654	115	22	\N	\N	0102000020E61000000200000019B79DFC59C451C013327188272F4540A3B79DFC59C451C0F6AB8888272F4540
655	115	24	\N	\N	0102000020E610000002000000A3B79DFC59C451C0F6AB8888272F454024B89DFC59C451C0A6D09E88272F4540
656	116	7	\N	\N	0102000020E61000000200000033138DFC59C451C0EA1B00B0242F454068138DFC59C451C0C01609B0242F4540
657	116	9	\N	\N	0102000020E61000000300000068138DFC59C451C0C01609B0242F4540BF3F95FC59C451C00450D315262F4540F29F99FC59C451C0DE2061D5262F4540
658	116	10	\N	\N	0102000020E610000002000000F29F99FC59C451C0DE2061D5262F4540A2299CFC59C451C087C67944272F4540
659	116	12	\N	\N	0102000020E610000002000000A2299CFC59C451C087C67944272F45402C2A9CFC59C451C070409144272F4540
660	116	14	\N	\N	0102000020E6100000020000002C2A9CFC59C451C070409144272F4540AD2A9CFC59C451C02365A744272F4540
661	118	19	\N	\N	0102000020E610000002000000AA13D8F15BC451C0F5138E44272F4540463FD8F15BC451C03E08EF4B272F4540
662	118	21	\N	\N	0102000020E610000002000000463FD8F15BC451C03E08EF4B272F45403E85D8F15BC451C033CAC557272F4540
663	118	38	\N	\N	0102000020E6100000020000003E85D8F15BC451C033CAC557272F4540584FB8125CC451C00BD48388272F4540
664	119	29	\N	\N	0102000020E61000000200000019CF7DD75AC451C05515F5AF242F454015BD48E85AC451C0EF18DBC8242F4540
665	119	31	\N	\N	0102000020E61000000200000015BD48E85AC451C0EF18DBC8242F4540EECC8BF85AC451C022A9F7E0242F4540
666	119	33	\N	\N	0102000020E610000003000000EECC8BF85AC451C022A9F7E0242F4540B269DA075BC451C075C7A9F7242F45407702681D5BC451C0DDB29E17252F4540
667	119	34	\N	\N	0102000020E6100000020000007702681D5BC451C0DDB29E17252F454022CCB9875BC451C0806842B5252F4540
668	119	35	\N	\N	0102000020E61000000200000022CCB9875BC451C0806842B5252F4540847900A15BC451C0E274BCDA252F4540
669	119	38	\N	\N	0102000020E610000002000000847900A15BC451C0E274BCDA252F4540817DD2F15BC451C09C769152262F4540
670	119	57	\N	\N	0102000020E610000002000000817DD2F15BC451C09C769152262F45408E81D5F15BC451C0548333D5262F4540
671	119	58	\N	\N	0102000020E6100000020000008E81D5F15BC451C0548333D5262F4540AA13D8F15BC451C0F5138E44272F4540
672	120	11	\N	\N	0102000020E6100000020000009E58D9505CC451C0C63F8944272F4540F122F19B5CC451C049F922D5262F4540
673	120	22	\N	\N	0102000020E610000002000000F122F19B5CC451C049F922D5262F45401D4904B05CC451C05AF321D5262F4540
674	123	9	\N	\N	0102000020E610000004000000CCF5DF1A5CC451C0792C9B94272F45408DADE61A5CC451C0F17E57B7282F4540A95DE71A5CC451C04B521DD5282F45401B49030D5CC451C0FDB7B8E9282F4540
675	123	12	\N	\N	0102000020E6100000030000001B49030D5CC451C0FDB7B8E9282F454089900B0D5CC451C012F620502A2F4540487626ED5BC451C034C5717F2A2F4540
676	123	18	\N	\N	0102000020E610000002000000487626ED5BC451C034C5717F2A2F454038B926ED5BC451C070ACC58A2A2F4540
677	124	21	\N	\N	0102000020E6100000020000009307107E5AC451C04E91DBDB1D2F4540442F86FC59C451C0A509E2DB1D2F4540
678	124	22	\N	\N	0102000020E610000002000000442F86FC59C451C0A509E2DB1D2F4540F7CA7EFC59C451C0030AE2DB1D2F4540
679	124	24	\N	\N	0102000020E610000002000000F7CA7EFC59C451C0030AE2DB1D2F4540C3167EFC59C451C00C0AE2DB1D2F4540
680	124	26	\N	\N	0102000020E610000002000000C3167EFC59C451C00C0AE2DB1D2F4540243F77FC59C451C0640AE2DB1D2F4540
681	124	29	\N	\N	0102000020E610000002000000243F77FC59C451C0640AE2DB1D2F454063B054FC58C451C073D5EEDB1D2F4540
682	124	30	\N	\N	0102000020E61000000200000063B054FC58C451C073D5EEDB1D2F4540A037DBDF58C451C08A41F0DB1D2F4540
683	124	31	\N	\N	0102000020E610000002000000A037DBDF58C451C08A41F0DB1D2F454055C88A7158C451C011C4F5DB1D2F4540
684	124	34	\N	\N	0102000020E61000000200000055C88A7158C451C011C4F5DB1D2F45403438DEE557C451C001BEFCDB1D2F4540
685	124	35	\N	\N	0102000020E6100000020000003438DEE557C451C001BEFCDB1D2F45406D03D7E557C451C05DBEFCDB1D2F4540
686	124	37	\N	\N	0102000020E6100000020000006D03D7E557C451C05DBEFCDB1D2F4540B953D6E557C451C066BEFCDB1D2F4540
687	124	39	\N	\N	0102000020E610000002000000B953D6E557C451C066BEFCDB1D2F4540DFA7CFE557C451C0BBBEFCDB1D2F4540
688	124	42	\N	\N	0102000020E610000002000000DFA7CFE557C451C0BBBEFCDB1D2F45403923494F57C451C06B4304DC1D2F4540
689	125	7	\N	\N	0102000020E61000000400000006316B6C67C451C05CE73F8F112F45403EB5636C67C451C0DC72E65D102F45403898DC6A67C451C0E18CA25B102F454016E6D96A67C451C04234A2ED0F2F4540
690	125	13	\N	\N	0102000020E61000000200000016E6D96A67C451C04234A2ED0F2F45403209425767C451C0663C95D00F2F4540
691	125	14	\N	\N	0102000020E6100000020000003209425767C451C0663C95D00F2F4540D6DFFF6F65C451C0913F21FE0C2F4540
692	126	4	\N	\N	0102000020E610000002000000427D6D6C67C451C0CA8901ED112F4540D0346B6C67C451C02C87DA8F112F4540
693	126	6	\N	\N	0102000020E610000002000000D0346B6C67C451C02C87DA8F112F4540B1316B6C67C451C05F1C5B8F112F4540
694	126	8	\N	\N	0102000020E610000002000000B1316B6C67C451C05F1C5B8F112F454006316B6C67C451C05CE73F8F112F4540
695	127	10	\N	\N	0102000020E610000002000000DD10836C67C451C0C79E635D152F45408F10836C67C451C08C3F575D152F4540
696	127	12	\N	\N	0102000020E6100000030000008F10836C67C451C08C3F575D152F4540A2C7776C67C451C0C24CE390132F4540DFF5716C67C451C0CAFC70A3122F4540
697	127	15	\N	\N	0102000020E610000002000000DFF5716C67C451C0CAFC70A3122F4540D9F3716C67C451C0EC6B1EA3122F4540
698	127	16	\N	\N	0102000020E610000002000000D9F3716C67C451C0EC6B1EA3122F45400C816D6C67C451C0CD299CED112F4540
699	127	18	\N	\N	0102000020E6100000020000000C816D6C67C451C0CD299CED112F4540ED7D6D6C67C451C0D4BE1CED112F4540
700	127	20	\N	\N	0102000020E610000002000000ED7D6D6C67C451C0D4BE1CED112F4540427D6D6C67C451C0CA8901ED112F4540
701	128	12	\N	\N	0102000020E610000002000000D6DFFF6F65C451C0913F21FE0C2F4540D683FE6F65C451C033BC19C60C2F4540
702	128	15	\N	\N	0102000020E610000002000000D683FE6F65C451C033BC19C60C2F45406D71FE6F65C451C040F922C30C2F4540
703	128	18	\N	\N	0102000020E6100000020000006D71FE6F65C451C040F922C30C2F45408946D56F65C451C0D1EB5422062F4540
704	128	20	\N	\N	0102000020E6100000020000008946D56F65C451C0D1EB5422062F4540E6E8850C65C451C04BBC158F052F4540
705	128	22	\N	\N	0102000020E610000002000000E6E8850C65C451C04BBC158F052F4540C4BB780C65C451C0C032EA6E032F4540
706	128	24	\N	\N	0102000020E610000003000000C4BB780C65C451C0C032EA6E032F4540C095152365C451C0083F5E4D032F45402D85132365C451C01E4D22F8022F4540
707	129	18	\N	\N	0102000020E610000002000000D6DFFF6F65C451C0913F21FE0C2F4540711B43B764C451C0643A31100E2F4540
708	129	21	\N	\N	0102000020E610000002000000711B43B764C451C0643A31100E2F4540D104B49F64C451C0DF7E24330E2F4540
709	129	22	\N	\N	0102000020E610000002000000D104B49F64C451C0DF7E24330E2F4540E743CA9D64C451C09A0EFB350E2F4540
710	129	23	\N	\N	0102000020E610000002000000E743CA9D64C451C09A0EFB350E2F45409B47326164C451C0CB77DF8F0E2F4540
711	129	26	\N	\N	0102000020E6100000020000009B47326164C451C0CB77DF8F0E2F45400B3F1A2864C451C044B692E40E2F4540
712	129	29	\N	\N	0102000020E6100000020000000B3F1A2864C451C044B692E40E2F4540368FDC1264C451C05CA715040F2F4540
713	129	35	\N	\N	0102000020E610000002000000368FDC1264C451C05CA715040F2F4540D731F2FC63C451C012D016040F2F4540
714	129	36	\N	\N	0102000020E610000002000000D731F2FC63C451C012D016040F2F4540B8BD444C63C451C0182820040F2F4540
715	130	8	\N	\N	0102000020E6100000020000000679A1D969C451C041361E8F112F45405478A1D969C451C00242028F112F4540
716	130	10	\N	\N	0102000020E6100000030000005478A1D969C451C00242028F112F4540570E97D969C451C001733CEB0F2F454031CB96D969C451C059DFA9E00F2F4540
717	130	15	\N	\N	0102000020E61000000200000031CB96D969C451C059DFA9E00F2F4540DA87E6E569C451C0222766CE0F2F4540
718	130	16	\N	\N	0102000020E610000002000000DA87E6E569C451C0222766CE0F2F4540828E99F36BC451C01A2381C20C2F4540
719	131	6	\N	\N	0102000020E61000000200000079CCA3D969C451C0ADD8DFEC112F4540C7CBA3D969C451C074E4C3EC112F4540
720	131	8	\N	\N	0102000020E610000002000000C7CBA3D969C451C074E4C3EC112F4540E17CA1D969C451C0EE92B98F112F4540
721	131	10	\N	\N	0102000020E610000002000000E17CA1D969C451C0EE92B98F112F4540467CA1D969C451C0554AA18F112F4540
722	131	12	\N	\N	0102000020E610000002000000467CA1D969C451C0554AA18F112F45400679A1D969C451C041361E8F112F4540
723	132	10	\N	\N	0102000020E610000002000000D7A3B9D969C451C0A3ED415D152F454025A3B9D969C451C04EF9255D152F4540
724	132	12	\N	\N	0102000020E61000000200000025A3B9D969C451C04EF9255D152F4540D5A2B9D969C451C00B44195D152F4540
725	132	15	\N	\N	0102000020E610000003000000D5A2B9D969C451C00B44195D152F45402A37AED969C451C0A29BC190132F45405252A8D969C451C0B8BA2EA3122F4540
726	132	16	\N	\N	0102000020E6100000020000005252A8D969C451C0B8BA2EA3122F454054D0A3D969C451C0BA357BED112F4540
727	132	18	\N	\N	0102000020E61000000200000054D0A3D969C451C0BA357BED112F4540B9CFA3D969C451C013ED62ED112F4540
728	132	20	\N	\N	0102000020E610000002000000B9CFA3D969C451C013ED62ED112F454079CCA3D969C451C0ADD8DFEC112F4540
729	133	2	\N	\N	0102000020E610000004000000828E99F36BC451C01A2381C20C2F45406B8A6DF36BC451C052CFB4E6052F454005682C326CC451C0D0CE9E89052F4540B8FD1E326CC451C062342173032F4540
730	133	4	\N	\N	0102000020E610000003000000B8FD1E326CC451C062342173032F4540F9408A196CC451C0C80DAF4E032F45409E2088196CC451C04F94ECF9022F4540
731	134	9	\N	\N	0102000020E610000002000000828E99F36BC451C01A2381C20C2F45405E243F606CC451C07BB197630D2F4540
732	134	10	\N	\N	0102000020E6100000020000005E243F606CC451C07BB197630D2F454036DD66A76CC451C081B817CD0D2F4540
733	134	13	\N	\N	0102000020E61000000200000036DD66A76CC451C081B817CD0D2F4540D2E0CE786DC451C0901393030F2F4540
734	134	18	\N	\N	0102000020E610000002000000D2E0CE786DC451C0901393030F2F45405C6C51F66DC451C074188C030F2F4540
735	135	7	\N	\N	0102000020E6100000040000001A8E96BE75C451C0EC1F738E112F45409D878EBE75C451C078AB195D102F4540906907BD75C451C000C7D55A102F4540768504BD75C451C0666ED5EC0F2F4540
736	135	13	\N	\N	0102000020E610000002000000768504BD75C451C0666ED5EC0F2F4540296854A775C451C04689ADCC0F2F4540
737	135	14	\N	\N	0102000020E610000002000000296854A775C451C04689ADCC0F2F45406450FA9B73C451C042A6B9C40C2F4540
738	136	8	\N	\N	0102000020E610000002000000ED0499BE75C451C057C234EC112F4540020199BE75C451C0B6BA9FEB112F4540
739	136	10	\N	\N	0102000020E610000002000000020199BE75C451C0B6BA9FEB112F45402E0099BE75C451C0EF1C80EB112F4540
740	136	12	\N	\N	0102000020E6100000020000002E0099BE75C451C0EF1C80EB112F4540769296BE75C451C077FC188F112F4540
741	136	14	\N	\N	0102000020E610000002000000769296BE75C451C077FC188F112F4540D58E96BE75C451C0F6E38E8E112F4540
742	136	16	\N	\N	0102000020E610000002000000D58E96BE75C451C0F6E38E8E112F45401A8E96BE75C451C0EC1F738E112F4540
743	137	18	\N	\N	0102000020E6100000020000007228B0BE75C451C034D7965C152F45401928B0BE75C451C00FA6895C152F4540
744	137	20	\N	\N	0102000020E6100000020000001928B0BE75C451C00FA6895C152F45405A26B0BE75C451C00D2D475C152F4540
745	137	23	\N	\N	0102000020E6100000020000005A26B0BE75C451C00D2D475C152F45408724B0BE75C451C052CF015C152F4540
746	137	26	\N	\N	0102000020E6100000020000008724B0BE75C451C052CF015C152F4540B323B0BE75C451C08031E25B152F4540
747	137	29	\N	\N	0102000020E610000002000000B323B0BE75C451C08031E25B152F45405223B0BE75C451C08DD6D35B152F4540
748	137	32	\N	\N	0102000020E6100000030000005223B0BE75C451C08DD6D35B152F4540080EA4BE75C451C040851690132F4540490999BE75C451C0E49EDAEC112F4540
749	137	34	\N	\N	0102000020E610000002000000490999BE75C451C0E49EDAEC112F4540A80599BE75C451C0608650EC112F4540
750	137	36	\N	\N	0102000020E610000002000000A80599BE75C451C0608650EC112F4540ED0499BE75C451C057C234EC112F4540
751	138	10	\N	\N	0102000020E6100000020000006450FA9B73C451C042A6B9C40C2F4540E942FA9B73C451C05F75B3C20C2F4540
752	138	13	\N	\N	0102000020E610000002000000E942FA9B73C451C05F75B3C20C2F45404B3CFA9B73C451C0651EB5C10C2F4540
753	138	16	\N	\N	0102000020E6100000020000004B3CFA9B73C451C0651EB5C10C2F4540D3A1CC9B73C451C09B52EDE8052F4540
754	138	17	\N	\N	0102000020E610000003000000D3A1CC9B73C451C09B52EDE8052F4540955B3F5B73C451C0AED23789052F4540E277315B73C451C04938BA72032F4540
755	138	19	\N	\N	0102000020E610000003000000E277315B73C451C04938BA72032F454047CF877573C451C05787A74B032F45409A79857573C451C0EE30DBF1022F4540
756	138	20	\N	\N	0102000020E6100000020000009A79857573C451C0EE30DBF1022F4540E068857573C451C0EFC857EF022F4540
757	139	15	\N	\N	0102000020E6100000020000006450FA9B73C451C042A6B9C40C2F45407E57F49873C451C02CE135C90C2F4540
758	139	17	\N	\N	0102000020E6100000020000007E57F49873C451C02CE135C90C2F45400F6A538573C451C04CA254E60C2F4540
759	139	19	\N	\N	0102000020E6100000020000000F6A538573C451C04CA254E60C2F454020ACEA3073C451C010628E630D2F4540
760	139	20	\N	\N	0102000020E61000000200000020ACEA3073C451C010628E630D2F4540968954EE72C451C0614157C60D2F4540
761	139	23	\N	\N	0102000020E610000002000000968954EE72C451C0614157C60D2F4540FCA40D3B72C451C012D64ED00E2F4540
762	139	26	\N	\N	0102000020E610000002000000FCA40D3B72C451C012D64ED00E2F4540F0FEAB1872C451C0119050030F2F4540
763	139	30	\N	\N	0102000020E610000002000000F0FEAB1872C451C0119050030F2F4540C846969771C451C03EE357030F2F4540
764	140	13	\N	\N	0102000020E610000002000000ACAC3F0D78C451C051CB508E112F4540EBAB3F0D78C451C0655A348E112F4540
765	140	15	\N	\N	0102000020E610000002000000EBAB3F0D78C451C0655A348E112F4540DDA73F0D78C451C08DD79B8D112F4540
766	140	17	\N	\N	0102000020E610000002000000DDA73F0D78C451C08DD79B8D112F4540D68F370D78C451C0DC56F75C102F4540
767	140	21	\N	\N	0102000020E610000003000000D68F370D78C451C0DC56F75C102F4540DD35ED1878C451C0CB22984B102F45400717EB1878C451C0C1DDCCFB0F2F4540
768	140	25	\N	\N	0102000020E6100000020000000717EB1878C451C0C1DDCCFB0F2F4540BB112C3A78C451C0D94877CA0F2F4540
769	140	26	\N	\N	0102000020E610000002000000BB112C3A78C451C0D94877CA0F2F454036628B457AC451C060F501C20C2F4540
770	141	8	\N	\N	0102000020E6100000020000005B2A420D78C451C0BA6D12EC112F45409A29420D78C451C0D6FCF5EB112F4540
771	141	10	\N	\N	0102000020E6100000020000009A29420D78C451C0D6FCF5EB112F45408C25420D78C451C01C7A5DEB112F4540
772	141	12	\N	\N	0102000020E6100000020000008C25420D78C451C01C7A5DEB112F45402DB13F0D78C451C03653FA8E112F4540
773	141	14	\N	\N	0102000020E6100000020000002DB13F0D78C451C03653FA8E112F45406FB03F0D78C451C0A664DE8E112F4540
774	141	16	\N	\N	0102000020E6100000020000006FB03F0D78C451C0A664DE8E112F4540ACAC3F0D78C451C051CB508E112F4540
775	142	16	\N	\N	0102000020E6100000020000004F8E590D78C451C09182745C152F45408E8D590D78C451C09211585C152F4540
776	142	18	\N	\N	0102000020E6100000020000008E8D590D78C451C09211585C152F4540328D590D78C451C0128F4A5C152F4540
777	142	21	\N	\N	0102000020E610000002000000328D590D78C451C0128F4A5C152F4540638B590D78C451C09583065C152F4540
778	142	24	\N	\N	0102000020E610000002000000638B590D78C451C09583065C152F45408089590D78C451C0458EBF5B152F4540
779	142	27	\N	\N	0102000020E6100000020000008089590D78C451C0458EBF5B152F4540A488590D78C451C0963A9F5B152F4540
780	142	28	\N	\N	0102000020E610000003000000A488590D78C451C0963A9F5B152F454031524D0D78C451C09F30F48F132F4540DC2E420D78C451C005F6BBEC112F4540
781	142	30	\N	\N	0102000020E610000002000000DC2E420D78C451C005F6BBEC112F45401E2E420D78C451C06607A0EC112F4540
782	142	32	\N	\N	0102000020E6100000020000001E2E420D78C451C06607A0EC112F45405B2A420D78C451C0BA6D12EC112F4540
783	143	9	\N	\N	0102000020E61000000200000036628B457AC451C060F501C20C2F4540B5608B457AC451C0E4ECC9C10C2F4540
784	143	12	\N	\N	0102000020E610000002000000B5608B457AC451C0E4ECC9C10C2F45400F5B8B457AC451C08683F7C00C2F4540
785	143	15	\N	\N	0102000020E6100000020000000F5B8B457AC451C08683F7C00C2F454098BF61457AC451C0920AF5B2062F4540
786	143	16	\N	\N	0102000020E61000000300000098BF61457AC451C0920AF5B2062F454021C604857AC451C061823D44062F45401D63F1847AC451C05E5CD772032F4540
787	143	18	\N	\N	0102000020E6100000030000001D63F1847AC451C05E5CD772032F4540DA4D666B7AC451C0F527F84C032F454055D6636B7AC451C03CE221F1022F4540
788	144	17	\N	\N	0102000020E61000000200000036628B457AC451C060F501C20C2F454090767BB27AC451C02B1D86630D2F4540
789	144	18	\N	\N	0102000020E61000000200000090767BB27AC451C02B1D86630D2F45408FC3B2E57AC451C0CC8875AF0D2F4540
790	144	21	\N	\N	0102000020E6100000020000008FC3B2E57AC451C0CC8875AF0D2F4540141035AE7BC451C02735BED80E2F4540
791	144	24	\N	\N	0102000020E610000002000000141035AE7BC451C02735BED80E2F45409D107FB87BC451C03780FFE70E2F4540
792	144	26	\N	\N	0102000020E6100000020000009D107FB87BC451C03780FFE70E2F454076E921CC7BC451C05E891C050F2F4540
793	144	28	\N	\N	0102000020E61000000200000076E921CC7BC451C05E891C050F2F454033F995D27BC451C094F5AD0E0F2F4540
794	144	34	\N	\N	0102000020E61000000200000033F995D27BC451C094F5AD0E0F2F454022AD4F527CC451C0015BA60E0F2F4540
795	145	8	\N	\N	0102000020E610000002000000F1DF1D9680C451C0874CF25B152F4540443E45C781C451C065A8DF5B152F4540
796	145	9	\N	\N	0102000020E610000002000000443E45C781C451C065A8DF5B152F45406676A8CC81C451C02454DF5B152F4540
797	145	10	\N	\N	0102000020E6100000020000006676A8CC81C451C02454DF5B152F45401A7DA9CC81C451C01454DF5B152F4540
798	145	12	\N	\N	0102000020E6100000020000001A7DA9CC81C451C01454DF5B152F4540BD9FA9ED81C451C00050DD5B152F4540
799	145	15	\N	\N	0102000020E610000002000000BD9FA9ED81C451C00050DD5B152F4540E621FDCC82C451C086ABCF5B152F4540
800	145	16	\N	\N	0102000020E610000002000000E621FDCC82C451C086ABCF5B152F4540B36325F982C451C0F9F8CC5B152F4540
801	146	3	\N	\N	0102000020E610000002000000B36325F982C451C0F9F8CC5B152F45407BA0D90584C451C0A56EBC5B152F4540
802	146	5	\N	\N	0102000020E6100000020000007BA0D90584C451C0A56EBC5B152F454067D0DA0584C451C0936EBC5B152F4540
803	146	6	\N	\N	0102000020E61000000200000067D0DA0584C451C0936EBC5B152F45404EF6E50584C451C0E36DBC5B152F4540
804	147	7	\N	\N	0102000020E6100000020000004EF6E50584C451C0E36DBC5B152F45406C07B02F84C451C03BD6B95B152F4540
805	147	9	\N	\N	0102000020E6100000020000006C07B02F84C451C03BD6B95B152F45405D0FB12F84C451C02BD6B95B152F4540
806	147	11	\N	\N	0102000020E6100000020000005D0FB12F84C451C02BD6B95B152F4540DB133F7D86C451C07743955B152F4540
807	147	13	\N	\N	0102000020E610000002000000DB133F7D86C451C07743955B152F45403E48407D86C451C06443955B152F4540
808	147	14	\N	\N	0102000020E6100000020000003E48407D86C451C06443955B152F454007984B7D86C451C0B042955B152F4540
809	148	15	\N	\N	0102000020E61000000200000007984B7D86C451C0B042955B152F4540FE63692688C451C0421E7A5B152F4540
810	148	16	\N	\N	0102000020E610000002000000FE63692688C451C0421E7A5B152F45404AE7A79788C451C04EE3725B152F4540
811	148	19	\N	\N	0102000020E6100000020000004AE7A79788C451C04EE3725B152F45403EC067BD88C451C04D7A705B152F4540
812	148	20	\N	\N	0102000020E6100000020000003EC067BD88C451C04D7A705B152F4540B0FBB69A8AC451C0C900525B152F4540
813	148	21	\N	\N	0102000020E610000002000000B0FBB69A8AC451C0C900525B152F45404A3F95408EC451C0EC60165B152F4540
814	148	22	\N	\N	0102000020E6100000020000004A3F95408EC451C0EC60165B152F454069275CF48EC451C082E60A5B152F4540
815	148	23	\N	\N	0102000020E61000000200000069275CF48EC451C082E60A5B152F45401D51EB1A90C451C00218F85A152F4540
816	148	24	\N	\N	0102000020E6100000020000001D51EB1A90C451C00218F85A152F454008BE191B90C451C00B15F85A152F4540
817	148	25	\N	\N	0102000020E61000000200000008BE191B90C451C00B15F85A152F45407DDB1A1B90C451C0F914F85A152F4540
818	148	27	\N	\N	0102000020E6100000020000007DDB1A1B90C451C0F914F85A152F4540EDB28E4190C451C079A0F55A152F4540
819	148	30	\N	\N	0102000020E610000002000000EDB28E4190C451C079A0F55A152F4540EE5B8D5191C451C0C842E45A152F4540
820	149	3	\N	\N	0102000020E610000002000000EE5B8D5191C451C0C842E45A152F45405820F13792C451C0D82ED55A152F4540
821	149	5	\N	\N	0102000020E6100000020000005820F13792C451C0D82ED55A152F45402663F23792C451C0C22ED55A152F4540
822	149	6	\N	\N	0102000020E6100000020000002663F23792C451C0C22ED55A152F4540563AFE3792C451C0FC2DD55A152F4540
823	150	3	\N	\N	0102000020E610000002000000563AFE3792C451C0FC2DD55A152F4540ED17217E92C451C01791D05A152F4540
824	150	4	\N	\N	0102000020E610000002000000ED17217E92C451C01791D05A152F45407E31227E92C451C00491D05A152F4540
825	150	6	\N	\N	0102000020E6100000020000007E31227E92C451C00491D05A152F454087DF94B493C451C0F225BC5A152F4540
826	151	4	\N	\N	0102000020E61000000200000087DF94B493C451C0F225BC5A152F4540D4DF8F9F94C451C0929AAC5A152F4540
827	151	5	\N	\N	0102000020E610000002000000D4DF8F9F94C451C0929AAC5A152F454067E3620595C451C02FDEA55A152F4540
828	151	7	\N	\N	0102000020E61000000200000067E3620595C451C02FDEA55A152F45404C2A640595C451C019DEA55A152F4540
829	151	8	\N	\N	0102000020E6100000020000004C2A640595C451C019DEA55A152F4540EA27700595C451C04EDDA55A152F4540
830	152	7	\N	\N	0102000020E610000002000000EA27700595C451C04EDDA55A152F4540B08424EB96C451C00B6B855A152F4540
831	152	10	\N	\N	0102000020E610000002000000B08424EB96C451C00B6B855A152F4540DBEB1D1197C451C0A1E1825A152F4540
832	152	11	\N	\N	0102000020E610000002000000DBEB1D1197C451C0A1E1825A152F4540376A304497C451C038787F5A152F4540
833	152	12	\N	\N	0102000020E610000002000000376A304497C451C038787F5A152F4540C98A314497C451C024787F5A152F4540
834	152	14	\N	\N	0102000020E610000002000000C98A314497C451C024787F5A152F4540A9E6A37A98C451C00CBB6A5A152F4540
835	153	8	\N	\N	0102000020E610000002000000A9E6A37A98C451C00CBB6A5A152F454065FEB9EC98C451C053F3625A152F4540
836	153	9	\N	\N	0102000020E61000000200000065FEB9EC98C451C053F3625A152F4540363E353F99C451C05D535D5A152F4540
837	153	10	\N	\N	0102000020E610000002000000363E353F99C451C05D535D5A152F4540D128EA929CC451C03F3E235A152F4540
838	153	11	\N	\N	0102000020E610000002000000D128EA929CC451C03F3E235A152F4540001E1D6D9EC451C0ABE7025A152F4540
839	153	12	\N	\N	0102000020E610000002000000001E1D6D9EC451C0ABE7025A152F45404C6DDF6D9EC451C06BDA025A152F4540
840	153	13	\N	\N	0102000020E6100000020000004C6DDF6D9EC451C06BDA025A152F454052F385939EC451C01D49005A152F4540
841	153	16	\N	\N	0102000020E61000000200000052F385939EC451C01D49005A152F45408B451B3E9FC451C011A7F459152F4540
842	154	6	\N	\N	0102000020E6100000020000008B451B3E9FC451C011A7F459152F4540BD65A774A0C451C07122DF59152F4540
843	154	7	\N	\N	0102000020E610000002000000BD65A774A0C451C07122DF59152F45402991A874A0C451C05C22DF59152F4540
844	154	9	\N	\N	0102000020E6100000020000002991A874A0C451C05C22DF59152F454085308284A0C451C03409DE59152F4540
845	154	11	\N	\N	0102000020E61000000200000085308284A0C451C03409DE59152F4540C7868384A0C451C01D09DE59152F4540
846	154	12	\N	\N	0102000020E610000002000000C7868384A0C451C01D09DE59152F454097149084A0C451C03E08DE59152F4540
847	156	3	\N	\N	0102000020E610000002000000DF9AB52FA2C451C07843C059152F45407D24604DA3C451C01E3FAC59152F4540
848	156	5	\N	\N	0102000020E6100000020000007D24604DA3C451C01E3FAC59152F4540577E614DA3C451C0063FAC59152F4540
849	156	6	\N	\N	0102000020E610000002000000577E614DA3C451C0063FAC59152F4540F12D6E4DA3C451C0223EAC59152F4540
850	157	19	\N	\N	0102000020E610000002000000F12D6E4DA3C451C0223EAC59152F4540E0864166A3C451C09C76AA59152F4540
851	157	21	\N	\N	0102000020E610000002000000E0864166A3C451C09C76AA59152F454070AD4266A3C451C08776AA59152F4540
852	157	23	\N	\N	0102000020E61000000200000070AD4266A3C451C08776AA59152F454051C9533DA5C451C0EEB28859152F4540
853	157	26	\N	\N	0102000020E61000000200000051C9533DA5C451C0EEB28859152F45402F604863A5C451C07CFA8559152F4540
854	157	27	\N	\N	0102000020E6100000020000002F604863A5C451C07CFA8559152F454046A80A64A5C451C08FEC8559152F4540
855	157	28	\N	\N	0102000020E61000000200000046A80A64A5C451C08FEC8559152F4540320FC03EA7C451C024E66359152F4540
856	157	29	\N	\N	0102000020E610000002000000320FC03EA7C451C024E66359152F4540544D3BE5AAC451C05BEB2059152F4540
857	157	30	\N	\N	0102000020E610000002000000544D3BE5AAC451C05BEB2059152F45402F168098ABC451C0F5111459152F4540
858	157	31	\N	\N	0102000020E6100000020000002F168098ABC451C0F5111459152F454071ED45BFACC451C02CF1FE58152F4540
859	157	32	\N	\N	0102000020E61000000200000071ED45BFACC451C02CF1FE58152F45407C4E75BFACC451C0C7EDFE58152F4540
860	157	33	\N	\N	0102000020E6100000020000007C4E75BFACC451C0C7EDFE58152F4540628D76BFACC451C0B0EDFE58152F4540
861	157	35	\N	\N	0102000020E610000002000000628D76BFACC451C0B0EDFE58152F45402573B4E5ACC451C0FE2FFC58152F4540
862	157	38	\N	\N	0102000020E6100000020000002573B4E5ACC451C0FE2FFC58152F45408385E7F5ADC451C068ADE858152F4540
863	158	3	\N	\N	0102000020E6100000020000008385E7F5ADC451C068ADE858152F454092D5C813AFC451C05FBAD358152F4540
864	158	5	\N	\N	0102000020E61000000200000092D5C813AFC451C05FBAD358152F4540303FCA13AFC451C045BAD358152F4540
865	158	6	\N	\N	0102000020E610000002000000303FCA13AFC451C045BAD358152F4540CE82D713AFC451C04CB9D358152F4540
866	159	4	\N	\N	0102000020E610000002000000CE82D713AFC451C04CB9D358152F4540BAA77C22AFC451C057A5D258152F4540
867	159	5	\N	\N	0102000020E610000002000000BAA77C22AFC451C057A5D258152F4540B4E27D22AFC451C040A5D258152F4540
868	159	7	\N	\N	0102000020E610000002000000B4E27D22AFC451C040A5D258152F4540BC43243BB0C451C0F6FCBD58152F4540
869	159	8	\N	\N	0102000020E610000002000000BC43243BB0C451C0F6FCBD58152F4540CF08EF58B0C451C097CBBB58152F4540
870	160	3	\N	\N	0102000020E610000002000000CF08EF58B0C451C097CBBB58152F454088B677D2B1C451C093DD9F58152F4540
871	160	5	\N	\N	0102000020E61000000200000088B677D2B1C451C093DD9F58152F45401D2479D2B1C451C078DD9F58152F4540
872	160	6	\N	\N	0102000020E6100000020000001D2479D2B1C451C078DD9F58152F4540FC8C86D2B1C451C07ADC9F58152F4540
873	161	8	\N	\N	0102000020E610000002000000FC8C86D2B1C451C07ADC9F58152F45408F974B69B3C451C0DB838158152F4540
874	161	11	\N	\N	0102000020E6100000020000008F974B69B3C451C0DB838158152F4540AC8770B5B3C451C0A1D57B58152F4540
875	161	12	\N	\N	0102000020E610000002000000AC8770B5B3C451C0A1D57B58152F4540E5AAA0B5B3C451C009D27B58152F4540
876	161	13	\N	\N	0102000020E610000002000000E5AAA0B5B3C451C009D27B58152F454088ECA1B5B3C451C0F1D17B58152F4540
877	161	15	\N	\N	0102000020E61000000200000088ECA1B5B3C451C0F1D17B58152F4540367B97DDB4C451C09EBD6558152F4540
878	161	16	\N	\N	0102000020E610000002000000367B97DDB4C451C09EBD6558152F454065C412ECB4C451C00BA96458152F4540
879	162	9	\N	\N	0102000020E61000000200000065C412ECB4C451C00BA96458152F454027FB0060B5C451C086DD5B58152F4540
880	162	10	\N	\N	0102000020E61000000200000027FB0060B5C451C086DD5B58152F45401EE3C4C2B9C451C0FAAF0658152F4540
881	162	12	\N	\N	0102000020E6100000020000001EE3C4C2B9C451C0FAAF0658152F4540C2DDCBC2B9C451C073AF0658152F4540
882	162	13	\N	\N	0102000020E610000002000000C2DDCBC2B9C451C073AF0658152F4540F464A714BBC451C0D20DED57152F4540
883	162	18	\N	\N	0102000020E610000002000000F464A714BBC451C0D20DED57152F454068E40B56BBC451C034E9DEB8152F4540
884	163	45	\N	\N	0102000020E61000000200000068E40B56BBC451C034E9DEB8152F4540F0EE245BBBC451C00185DEB8152F4540
885	163	47	\N	\N	0102000020E610000002000000F0EE245BBBC451C00185DEB8152F454013ECF35EBBC451C0263ADEB8152F4540
886	163	52	\N	\N	0102000020E61000000300000013ECF35EBBC451C0263ADEB8152F454093E54990BBC451C04716AB6F152F45406FB0FADEBCC451C0773E916F152F4540
887	163	53	\N	\N	0102000020E6100000020000006FB0FADEBCC451C0773E916F152F45407019B07CBDC451C00C11856F152F4540
888	163	56	\N	\N	0102000020E6100000020000007019B07CBDC451C00C11856F152F4540B8D0E0F6BDC451C0B8A17B6F152F4540
889	163	59	\N	\N	0102000020E610000002000000B8D0E0F6BDC451C0B8A17B6F152F4540AC002859BEC451C0100B746F152F4540
890	163	73	\N	\N	0102000020E610000002000000AC002859BEC451C0100B746F152F45406EF5445CBEC451C0D996D56A152F4540
891	163	74	\N	\N	0102000020E6100000020000006EF5445CBEC451C0D996D56A152F454083835523C0C451C06728A6C7122F4540
892	163	77	\N	\N	0102000020E61000000200000083835523C0C451C06728A6C7122F4540A6A3E52FC0C451C0382AA5C7122F4540
893	163	78	\N	\N	0102000020E610000002000000A6A3E52FC0C451C0382AA5C7122F4540F14EE62FC0C451C02A2AA5C7122F4540
894	163	81	\N	\N	0102000020E610000002000000F14EE62FC0C451C02A2AA5C7122F4540E0914F04C4C451C0A7AD57C7122F4540
895	163	83	\N	\N	0102000020E610000002000000E0914F04C4C451C0A7AD57C7122F45407782CE87C4C451C01E494DC7122F4540
896	163	85	\N	\N	0102000020E6100000020000007782CE87C4C451C01E494DC7122F4540B0C122B7C5C451C0E84F35C7122F4540
897	163	86	\N	\N	0102000020E610000002000000B0C122B7C5C451C0E84F35C7122F45408D0326B7C5C451C0A64F35C7122F4540
898	163	89	\N	\N	0102000020E6100000020000008D0326B7C5C451C0A64F35C7122F45405F266CB3C6C451C06D5F21C7122F4540
899	163	90	\N	\N	0102000020E6100000020000005F266CB3C6C451C06D5F21C7122F4540874E2B21C7C451C0F0B218C7122F4540
900	164	15	\N	\N	0102000020E610000002000000874E2B21C7C451C0F0B218C7122F454025481023C7C451C06D2049C4122F4540
901	164	22	\N	\N	0102000020E61000000200000025481023C7C451C06D2049C4122F45409FC6CB14C9C451C0792E21C4122F4540
902	164	30	\N	\N	0102000020E6100000020000009FC6CB14C9C451C0792E21C4122F45409DF7751FC9C451C0334D4EB4122F4540
903	165	6	\N	\N	0102000020E6100000020000009DF7751FC9C451C0334D4EB4122F45404B7B467CC9C451C0D7CF46B4122F4540
904	165	9	\N	\N	0102000020E6100000020000004B7B467CC9C451C0D7CF46B4122F4540F888E054CAC451C0495535B4122F4540
905	165	11	\N	\N	0102000020E610000002000000F888E054CAC451C0495535B4122F4540660AE354CAC451C0155535B4122F4540
906	165	12	\N	\N	0102000020E610000002000000660AE354CAC451C0155535B4122F454094F5FF54CAC451C0C05235B4122F4540
907	166	23	\N	\N	0102000020E61000000200000094F5FF54CAC451C0C05235B4122F4540812552ACCBC451C09F4819B4122F4540
908	166	25	\N	\N	0102000020E610000002000000812552ACCBC451C09F4819B4122F454099F89D2BCCC451C01FE30EB4122F4540
909	166	27	\N	\N	0102000020E61000000200000099F89D2BCCC451C01FE30EB4122F4540427CDDAACCC451C0A17E04B4122F4540
910	166	28	\N	\N	0102000020E610000002000000427CDDAACCC451C0A17E04B4122F45402C4CB60ACDC451C0ABAAFCB3122F4540
911	166	30	\N	\N	0102000020E6100000020000002C4CB60ACDC451C0ABAAFCB3122F45406E6EB70ACDC451C094AAFCB3122F4540
912	166	32	\N	\N	0102000020E6100000020000006E6EB70ACDC451C094AAFCB3122F4540BB42211FCDC451C0C6FFFAB3122F4540
913	166	33	\N	\N	0102000020E610000002000000BB42211FCDC451C0C6FFFAB3122F45407D390CF2CDC451C0ECC5E9B3122F4540
914	166	36	\N	\N	0102000020E6100000020000007D390CF2CDC451C0ECC5E9B3122F4540E4BB33B1CEC451C04829DAB3122F4540
915	166	37	\N	\N	0102000020E610000002000000E4BB33B1CEC451C04829DAB3122F454001741233CFC451C0F98DCFB3122F4540
916	166	40	\N	\N	0102000020E61000000200000001741233CFC451C0F98DCFB3122F4540F7A61D33CFC451C00E8DCFB3122F4540
917	166	42	\N	\N	0102000020E610000002000000F7A61D33CFC451C00E8DCFB3122F4540E0CD1E33CFC451C0F68CCFB3122F4540
918	166	44	\N	\N	0102000020E610000002000000E0CD1E33CFC451C0F68CCFB3122F4540AA952A33CFC451C0008CCFB3122F4540
919	166	45	\N	\N	0102000020E610000002000000AA952A33CFC451C0008CCFB3122F45405F9E5039D0C451C00523BAB3122F4540
920	166	46	\N	\N	0102000020E6100000020000005F9E5039D0C451C00523BAB3122F4540EC52B049D0C451C0ADCCB8B3122F4540
921	167	5	\N	\N	0102000020E610000002000000EC52B049D0C451C0ADCCB8B3122F4540044FB049D0C451C0C09C50B3122F4540
922	167	7	\N	\N	0102000020E610000002000000044FB049D0C451C0C09C50B3122F4540364EB049D0C451C081283BB3122F4540
923	167	10	\N	\N	0102000020E610000003000000364EB049D0C451C081283BB3122F454015C5A849D0C451C01B7449EA112F454017F29449D0C451C0449EA8D90F2F4540
924	168	15	\N	\N	0102000020E610000002000000EC52B049D0C451C0ADCCB8B3122F454042C1B849D1C451C0469AA3B3122F4540
925	168	18	\N	\N	0102000020E61000000200000042C1B849D1C451C0469AA3B3122F4540B5F0C349D1C451C05999A3B3122F4540
926	168	20	\N	\N	0102000020E610000002000000B5F0C349D1C451C05999A3B3122F45404217C549D1C451C04199A3B3122F4540
927	168	22	\N	\N	0102000020E6100000020000004217C549D1C451C04199A3B3122F45405BDBD049D1C451C04798A3B3122F4540
928	168	23	\N	\N	0102000020E6100000020000005BDBD049D1C451C04798A3B3122F454065C152D0D1C451C0827598B3122F4540
929	168	26	\N	\N	0102000020E61000000200000065C152D0D1C451C0827598B3122F4540DBAB5931D2C451C01A6D90B3122F4540
930	168	29	\N	\N	0102000020E610000002000000DBAB5931D2C451C01A6D90B3122F4540DFA78B89D2C451C0E11F89B3122F4540
931	168	30	\N	\N	0102000020E610000002000000DFA78B89D2C451C0E11F89B3122F4540D676B289D2C451C0AA1C89B3122F4540
932	169	3	\N	\N	0102000020E610000002000000D676B289D2C451C0AA1C89B3122F4540E82923BDD2C451C0CBD584B3122F4540
933	169	6	\N	\N	0102000020E610000002000000E82923BDD2C451C0CBD584B3122F4540A94A0CDFD2C451C0070482B3122F4540
934	170	13	\N	\N	0102000020E610000002000000A94A0CDFD2C451C0070482B3122F454067AA0AC5D3C451C005A0405E112F4540
935	170	15	\N	\N	0102000020E61000000200000067AA0AC5D3C451C005A0405E112F4540F94E2817D4C451C0108C69E4102F4540
936	170	17	\N	\N	0102000020E610000002000000F94E2817D4C451C0108C69E4102F4540044D53C7D4C451C0847405DF0F2F4540
937	170	19	\N	\N	0102000020E610000002000000044D53C7D4C451C0847405DF0F2F45406AE9451AD5C451C03462F2630F2F4540
938	170	20	\N	\N	0102000020E6100000020000006AE9451AD5C451C03462F2630F2F45406D55A36FD5C451C01A2549E50E2F4540
939	170	21	\N	\N	0102000020E6100000020000006D55A36FD5C451C01A2549E50E2F4540AB764479D5C451C0B67BFFD60E2F4540
940	170	24	\N	\N	0102000020E610000005000000AB764479D5C451C0B67BFFD60E2F454021BDF7BDD5C451C0F52E10710E2F4540E32BF909D6C451C056CC09710E2F4540CEB39E4AD6C451C0332B1E110E2F454073719C4AD6C451C0C9D70BD60D2F4540
941	170	25	\N	\N	0102000020E61000000200000073719C4AD6C451C0C9D70BD60D2F4540A6709C4AD6C451C08AD3F6D50D2F4540
942	170	26	\N	\N	0102000020E610000002000000A6709C4AD6C451C08AD3F6D50D2F4540A96F9C4AD6C451C0F708DDD50D2F4540
943	171	6	\N	\N	0102000020E610000002000000A96F9C4AD6C451C0F708DDD50D2F4540215D894AD6C451C05DCE2BE30B2F4540
944	171	8	\N	\N	0102000020E610000002000000215D894AD6C451C05DCE2BE30B2F45406196834AD6C451C0706C224C0B2F4540
945	171	10	\N	\N	0102000020E6100000020000006196834AD6C451C0706C224C0B2F4540352B754AD6C451C03E1E20D3092F4540
946	171	12	\N	\N	0102000020E610000002000000352B754AD6C451C03E1E20D3092F4540B958574AD6C451C0BF985AC7062F4540
947	173	4	\N	\N	0102000020E610000002000000A96F9C4AD6C451C0F708DDD50D2F4540C76D874ED6C451C08BB4DCD50D2F4540
948	173	7	\N	\N	0102000020E610000002000000C76D874ED6C451C08BB4DCD50D2F45407CF08F4ED6C451C0D4B3DCD50D2F4540
949	173	8	\N	\N	0102000020E6100000030000007CF08F4ED6C451C0D4B3DCD50D2F4540525622A7D6C451C05B3FD5D50D2F4540074D3EC2D7C451C0AC5CBDD50D2F4540
950	174	9	\N	\N	0102000020E610000002000000A94A0CDFD2C451C0070482B3122F4540A34230EAD3C451C081CC873F142F4540
951	174	11	\N	\N	0102000020E610000002000000A34230EAD3C451C081CC873F142F4540230698DCD4C451C0AC66E2A6152F4540
952	174	13	\N	\N	0102000020E610000002000000230698DCD4C451C0AC66E2A6152F4540F3D42CA3D5C451C0B17445CD162F4540
953	174	14	\N	\N	0102000020E610000003000000F3D42CA3D5C451C0B17445CD162F454099C0AE23D6C451C030FFC68B172F4540EB8CD523D6C451C01496BA821B2F4540
954	174	18	\N	\N	0102000020E610000003000000EB8CD523D6C451C01496BA821B2F45407740CF4ED6C451C0F4F86FC21B2F45401054D64ED6C451C0500E757B1C2F4540
955	175	4	\N	\N	0102000020E6100000020000001054D64ED6C451C0500E757B1C2F45404275E34ED6C451C00207BDD21D2F4540
956	175	5	\N	\N	0102000020E6100000020000004275E34ED6C451C00207BDD21D2F45406A77E34ED6C451C00861F5D21D2F4540
957	175	8	\N	\N	0102000020E6100000020000006A77E34ED6C451C00861F5D21D2F4540523FE94ED6C451C0802D1A6A1E2F4540
958	176	15	\N	\N	0102000020E6100000020000005D679354D4C451C00B829F7B1C2F45406FC3B0D1D3C451C0A16DAA7B1C2F4540
959	176	16	\N	\N	0102000020E6100000030000006FC3B0D1D3C451C0A16DAA7B1C2F45401BED7639D3C451C00821B77B1C2F4540866340DFD2C451C0D4A2BE7B1C2F4540
960	176	19	\N	\N	0102000020E610000002000000866340DFD2C451C0D4A2BE7B1C2F4540BBEF52B8D2C451C019E0C17B1C2F4540
961	176	27	\N	\N	0102000020E610000002000000BBEF52B8D2C451C019E0C17B1C2F454008BBA128D2C451C042CEF5501D2F4540
962	176	28	\N	\N	0102000020E61000000200000008BBA128D2C451C042CEF5501D2F4540CF0B57F9D1C451C0450F21971D2F4540
963	176	30	\N	\N	0102000020E610000002000000CF0B57F9D1C451C0450F21971D2F4540E7B38DD0D1C451C0815EA5D31D2F4540
964	178	4	\N	\N	0102000020E6100000020000001054D64ED6C451C0500E757B1C2F45407F3EEB4AD6C451C0A562757B1C2F4540
965	178	7	\N	\N	0102000020E6100000020000007F3EEB4AD6C451C0A562757B1C2F45408C1FCC4AD6C451C04265757B1C2F4540
966	178	8	\N	\N	0102000020E6100000030000008C1FCC4AD6C451C04265757B1C2F4540F5C50DECD5C451C0585C7D7B1C2F4540B54BF1D0D4C451C0C91A957B1C2F4540
967	179	21	\N	\N	0102000020E610000002000000E7B38DD0D1C451C0815EA5D31D2F4540420E0C4AD1C451C05F76B0D31D2F4540
968	179	22	\N	\N	0102000020E610000002000000420E0C4AD1C451C05F76B0D31D2F45401A3C004AD1C451C05877B0D31D2F4540
969	179	24	\N	\N	0102000020E6100000020000001A3C004AD1C451C05877B0D31D2F45402D14FF49D1C451C07177B0D31D2F4540
970	179	26	\N	\N	0102000020E6100000020000002D14FF49D1C451C07177B0D31D2F45405CD7F349D1C451C05E78B0D31D2F4540
971	179	29	\N	\N	0102000020E6100000020000005CD7F349D1C451C05E78B0D31D2F4540CF0BEB49D0C451C01496C5D31D2F4540
972	179	32	\N	\N	0102000020E610000002000000CF0BEB49D0C451C01496C5D31D2F454079B8DE49D0C451C01997C5D31D2F4540
973	179	33	\N	\N	0102000020E61000000200000079B8DE49D0C451C01997C5D31D2F4540F6418C39D0C451C0B6EFC6D31D2F4540
974	179	34	\N	\N	0102000020E610000002000000F6418C39D0C451C0B6EFC6D31D2F4540FB186433CFC451C0B08EDCD31D2F4540
975	179	35	\N	\N	0102000020E610000002000000FB186433CFC451C0B08EDCD31D2F4540DE745833CFC451C0A68FDCD31D2F4540
976	179	37	\N	\N	0102000020E610000002000000DE745833CFC451C0A68FDCD31D2F454072515733CFC451C0BE8FDCD31D2F4540
977	179	39	\N	\N	0102000020E61000000200000072515733CFC451C0BE8FDCD31D2F454066404C33CFC451C0A890DCD31D2F4540
978	179	42	\N	\N	0102000020E61000000200000066404C33CFC451C0A890DCD31D2F454099E26DB1CEC451C09A46E7D31D2F4540
979	180	7	\N	\N	0102000020E610000002000000E7B38DD0D1C451C0815EA5D31D2F4540D70D6BD3D1C451C05486E4D71D2F4540
980	180	9	\N	\N	0102000020E610000002000000D70D6BD3D1C451C05486E4D71D2F45408CE9FF99D2C451C0838C47FE1E2F4540
981	180	10	\N	\N	0102000020E6100000020000008CE9FF99D2C451C0838C47FE1E2F4540A5AB63BDD2C451C07F2CBE321F2F4540
982	180	14	\N	\N	0102000020E610000002000000A5AB63BDD2C451C07F2CBE321F2F4540961768BDD2C451C00461B3A71F2F4540
983	181	8	\N	\N	0102000020E610000002000000961768BDD2C451C00461B3A71F2F454096C551FED2C451C0AA2FEE07202F4540
984	181	9	\N	\N	0102000020E61000000200000096C551FED2C451C0AA2FEE07202F4540C289F301D3C451C0A383500D202F4540
985	181	11	\N	\N	0102000020E610000002000000C289F301D3C451C0A383500D202F454007EBA902D3C451C0F1E15E0E202F4540
986	181	14	\N	\N	0102000020E61000000200000007EBA902D3C451C0F1E15E0E202F4540026E3552D3C451C0A2AE4A84202F4540
987	181	16	\N	\N	0102000020E610000002000000026E3552D3C451C0A2AE4A84202F4540A5244D60D3C451C0D9EB2E99202F4540
988	182	21	\N	\N	0102000020E610000002000000961768BDD2C451C00461B3A71F2F4540A9B89E94D2C451C0A6B737E41F2F4540
989	182	23	\N	\N	0102000020E610000002000000A9B89E94D2C451C0A6B737E41F2F45408D78978AD2C451C030DD18F31F2F4540
990	182	33	\N	\N	0102000020E6100000020000008D78978AD2C451C030DD18F31F2F4540A86BC08AD2C451C021C1F62E242F4540
991	182	34	\N	\N	0102000020E610000002000000A86BC08AD2C451C021C1F62E242F454063788869D2C451C0846B4060242F4540
992	182	36	\N	\N	0102000020E61000000200000063788869D2C451C0846B4060242F4540A4956761D2C451C0BAEA4F6C242F4540
993	182	39	\N	\N	0102000020E610000002000000A4956761D2C451C0BAEA4F6C242F454011300B5FD2C451C083AFD06F242F4540
994	182	40	\N	\N	0102000020E61000000200000011300B5FD2C451C083AFD06F242F454077940854D2C451C083C52680242F4540
995	182	42	\N	\N	0102000020E61000000200000077940854D2C451C083C52680242F4540DA08B931D2C451C0B5480FB3242F4540
996	183	7	\N	\N	0102000020E610000002000000DA08B931D2C451C0B5480FB3242F45407328B2D0D1C451C0545317B3242F4540
997	183	10	\N	\N	0102000020E6100000020000007328B2D0D1C451C0545317B3242F45403630304AD1C451C02E7922B3242F4540
998	183	11	\N	\N	0102000020E6100000020000003630304AD1C451C02E7922B3242F45401670244AD1C451C0287A22B3242F4540
999	183	13	\N	\N	0102000020E6100000020000001670244AD1C451C0287A22B3242F4540ED49234AD1C451C0407A22B3242F4540
1000	183	14	\N	\N	0102000020E610000002000000ED49234AD1C451C0407A22B3242F4540411E184AD1C451C02D7B22B3242F4540
1001	184	9	\N	\N	0102000020E610000002000000411E184AD1C451C02D7B22B3242F4540E97B0F4AD0C451C009A237B3242F4540
1002	184	12	\N	\N	0102000020E610000002000000E97B0F4AD0C451C009A237B3242F45401B2F034AD0C451C00DA337B3242F4540
1003	184	13	\N	\N	0102000020E6100000030000001B2F034AD0C451C00DA337B3242F4540C652C43ED0C451C0E29038B3242F4540AE33B039D0C451C0ECFB38B3242F4540
1004	184	14	\N	\N	0102000020E610000002000000AE33B039D0C451C0ECFB38B3242F4540166D8833CFC451C023914EB3242F4540
1005	184	15	\N	\N	0102000020E610000002000000166D8833CFC451C023914EB3242F454086C27C33CFC451C019924EB3242F4540
1006	184	17	\N	\N	0102000020E61000000200000086C27C33CFC451C019924EB3242F4540799E7B33CFC451C031924EB3242F4540
1007	184	18	\N	\N	0102000020E610000002000000799E7B33CFC451C031924EB3242F45404B877033CFC451C01B934EB3242F4540
1008	185	10	\N	\N	0102000020E61000000200000015C28B33CFC451C0549E028C272F45406CC38B33CFC451C08270268C272F4540
1009	185	12	\N	\N	0102000020E6100000020000006CC38B33CFC451C08270268C272F4540CCC48B33CFC451C0E24C4B8C272F4540
1010	185	14	\N	\N	0102000020E610000002000000CCC48B33CFC451C0E24C4B8C272F45405C728C33CFC451C02E09709E272F4540
1011	185	16	\N	\N	0102000020E6100000020000005C728C33CFC451C02E09709E272F4540C9738C33CFC451C02939969E272F4540
1012	185	18	\N	\N	0102000020E610000002000000C9738C33CFC451C02939969E272F45403C758C33CFC451C0B3FEBC9E272F4540
1013	185	20	\N	\N	0102000020E6100000040000003C758C33CFC451C0B3FEBC9E272F4540F4129733CFC451C0E5B2D6BA282F4540AA4D9933CFC451C0AC857FF6282F4540C8BAA533CFC451C0E3530A432A2F4540
1014	186	17	\N	\N	0102000020E610000002000000EA378933CFC451C0E9320B48272F454041398933CFC451C004052F48272F4540
1015	186	19	\N	\N	0102000020E61000000200000041398933CFC451C004052F48272F45409C3A8933CFC451C0A9575348272F4540
1016	186	21	\N	\N	0102000020E6100000020000009C3A8933CFC451C0A9575348272F4540A63A8933CFC451C0E96A5448272F4540
1017	186	23	\N	\N	0102000020E610000002000000A63A8933CFC451C0E96A5448272F4540FAAD8933CFC451C020B36254272F4540
1018	186	26	\N	\N	0102000020E610000002000000FAAD8933CFC451C020B36254272F454031E88933CFC451C06A9E785A272F4540
1019	186	28	\N	\N	0102000020E61000000200000031E88933CFC451C06A9E785A272F45409EE98933CFC451C04ECE9E5A272F4540
1020	186	30	\N	\N	0102000020E6100000020000009EE98933CFC451C04ECE9E5A272F454011EB8933CFC451C0C093C55A272F4540
1021	186	32	\N	\N	0102000020E61000000200000011EB8933CFC451C0C093C55A272F4540B0C08B33CFC451C0FA49DD8B272F4540
1022	186	34	\N	\N	0102000020E610000002000000B0C08B33CFC451C0FA49DD8B272F454015C28B33CFC451C0549E028C272F4540
1023	187	14	\N	\N	0102000020E6100000020000004B877033CFC451C01B934EB3242F4540A2887033CFC451C0376572B3242F4540
1024	187	16	\N	\N	0102000020E610000002000000A2887033CFC451C0376572B3242F454035897033CFC451C0CAD181B3242F4540
1025	187	19	\N	\N	0102000020E61000000200000035897033CFC451C0CAD181B3242F454083367133CFC451C09FA89FC5242F4540
1026	187	20	\N	\N	0102000020E61000000200000083367133CFC451C09FA89FC5242F454032377133CFC451C0EFF4B1C5242F4540
1027	187	23	\N	\N	0102000020E61000000200000032377133CFC451C0EFF4B1C5242F45409F387133CFC451C0D024D8C5242F4540
1028	187	26	\N	\N	0102000020E6100000030000009F387133CFC451C0D024D8C5242F45400CE77D33CFC451C0311E3719262F45402ECC8333CFC451C03792F9B6262F4540
1029	187	27	\N	\N	0102000020E6100000020000002ECC8333CFC451C03792F9B6262F454085368933CFC451C084DEE547272F4540
1030	187	28	\N	\N	0102000020E61000000200000085368933CFC451C084DEE547272F4540EA378933CFC451C0E9320B48272F4540
1031	188	25	\N	\N	0102000020E610000002000000A462240BCDC451C02DDB2F8C272F45400164240BCDC451C06198548C272F4540
1032	188	27	\N	\N	0102000020E6100000020000000164240BCDC451C06198548C272F4540D411250BCDC451C0D5E9A19E272F4540
1033	188	29	\N	\N	0102000020E610000002000000D411250BCDC451C0D5E9A19E272F45402F13250BCDC451C07675C69E272F4540
1034	188	31	\N	\N	0102000020E6100000020000002F13250BCDC451C07675C69E272F45409514250BCDC451C01213EC9E272F4540
1035	188	33	\N	\N	0102000020E6100000020000009514250BCDC451C01213EC9E272F4540FF15250BCDC451C0C942129F272F4540
1036	188	35	\N	\N	0102000020E610000003000000FF15250BCDC451C0C942129F272F4540C99E2F0BCDC451C0C1EF03BB282F45409D91300BCDC451C0BB2B95D4282F4540
1037	188	39	\N	\N	0102000020E6100000020000009D91300BCDC451C0BB2B95D4282F454025DB8F1FCDC451C07D95C8F2282F4540
1038	188	47	\N	\N	0102000020E61000000200000025DB8F1FCDC451C07D95C8F2282F454090589C1FCDC451C0964D59432A2F4540
1039	188	48	\N	\N	0102000020E61000000200000090589C1FCDC451C0964D59432A2F4540DF599C1FCDC451C0D9927C432A2F4540
1040	188	49	\N	\N	0102000020E610000002000000DF599C1FCDC451C0D9927C432A2F45406F5A9C1FCDC451C0CFB48B432A2F4540
1041	188	50	\N	\N	0102000020E6100000020000006F5A9C1FCDC451C0CFB48B432A2F4540287C9C1FCDC451C0C26A18472A2F4540
1042	189	19	\N	\N	0102000020E6100000020000001FDD210BCDC451C0C46F3848272F45407CDE210BCDC451C0FC2C5D48272F4540
1043	189	21	\N	\N	0102000020E6100000020000007CDE210BCDC451C0FC2C5D48272F4540CBDF210BCDC451C0D26C8048272F4540
1044	189	23	\N	\N	0102000020E610000002000000CBDF210BCDC451C0D26C8048272F45401EE1210BCDC451C0DD29A448272F4540
1045	189	25	\N	\N	0102000020E6100000020000001EE1210BCDC451C0DD29A448272F454028E1210BCDC451C0AB38A548272F4540
1046	189	27	\N	\N	0102000020E61000000200000028E1210BCDC451C0AB38A548272F4540A953220BCDC451C01B83B354272F4540
1047	189	30	\N	\N	0102000020E610000002000000A953220BCDC451C01B83B354272F45404F8C220BCDC451C03A7EAA5A272F4540
1048	189	32	\N	\N	0102000020E6100000020000004F8C220BCDC451C03A7EAA5A272F4540AA8D220BCDC451C0E309CF5A272F4540
1049	189	34	\N	\N	0102000020E610000002000000AA8D220BCDC451C0E309CF5A272F4540108F220BCDC451C082A7F45A272F4540
1050	189	36	\N	\N	0102000020E610000002000000108F220BCDC451C082A7F45A272F45407A90220BCDC451C03ED71A5B272F4540
1051	189	38	\N	\N	0102000020E6100000020000007A90220BCDC451C03ED71A5B272F4540A462240BCDC451C02DDB2F8C272F4540
1052	190	24	\N	\N	0102000020E6100000020000004B877033CFC451C01B934EB3242F454029F991B1CEC451C0CC3A59B3242F4540
1053	190	25	\N	\N	0102000020E61000000300000029F991B1CEC451C0CC3A59B3242F4540CFBB1C28CEC451C0E08164B3242F45405B801FEBCDC451C01D8069B3242F4540
1054	190	32	\N	\N	0102000020E6100000020000005B801FEBCDC451C01D8069B3242F45402E75E7D3CDC451C02CDCDCD5242F4540
1055	190	35	\N	\N	0102000020E6100000020000002E75E7D3CDC451C02CDCDCD5242F454028AE150BCDC451C0071FD3FF252F4540
1056	190	48	\N	\N	0102000020E61000000300000028AE150BCDC451C0071FD3FF252F4540FCA0160BCDC451C0075B6419262F45401FDD210BCDC451C0C46F3848272F4540
1057	191	7	\N	\N	0102000020E6100000020000005189334AD1C451C05B86D68B272F4540BA8A334AD1C451C0C5F5FB8B272F4540
1058	191	9	\N	\N	0102000020E610000002000000BA8A334AD1C451C0C5F5FB8B272F4540BE3A344AD1C451C07501429E272F4540
1059	191	11	\N	\N	0102000020E610000002000000BE3A344AD1C451C07501429E272F4540393C344AD1C451C0FC57699E272F4540
1060	191	13	\N	\N	0102000020E610000004000000393C344AD1C451C0FC57699E272F45403FEE3E4AD1C451C0EA9AAABA282F4540E82C414AD1C451C0B26D53F6282F4540B1AE4D4AD1C451C0FADBB9422A2F4540
1061	191	14	\N	\N	0102000020E610000002000000B1AE4D4AD1C451C0FADBB9422A2F45400FB04D4AD1C451C0E83BDE422A2F4540
1062	192	15	\N	\N	0102000020E610000002000000A5FA304AD1C451C0F21ADF47272F454008FC304AD1C451C08BFE0348272F4540
1063	192	17	\N	\N	0102000020E61000000200000008FC304AD1C451C08BFE0348272F454013FC304AD1C451C01B160548272F4540
1064	192	19	\N	\N	0102000020E61000000200000013FC304AD1C451C01B160548272F45403370314AD1C451C02A5C1354272F4540
1065	192	22	\N	\N	0102000020E6100000020000003370314AD1C451C02A5C1354272F454012AC314AD1C451C033964A5A272F4540
1066	192	24	\N	\N	0102000020E61000000200000012AC314AD1C451C033964A5A272F45408DAD314AD1C451C0B4EC715A272F4540
1067	192	26	\N	\N	0102000020E6100000020000008DAD314AD1C451C0B4EC715A272F45408686334AD1C451C0C43F8C8B272F4540
1068	192	28	\N	\N	0102000020E6100000020000008686334AD1C451C0C43F8C8B272F4540F387334AD1C451C08A26B28B272F4540
1069	192	30	\N	\N	0102000020E610000002000000F387334AD1C451C08A26B28B272F45405189334AD1C451C05B86D68B272F4540
1070	193	11	\N	\N	0102000020E610000002000000411E184AD1C451C02D7B22B3242F4540D81E184AD1C451C0212532B3242F4540
1071	193	13	\N	\N	0102000020E610000002000000D81E184AD1C451C0212532B3242F4540D8CD184AD1C451C07A2F5DC5242F4540
1072	193	14	\N	\N	0102000020E610000002000000D8CD184AD1C451C07A2F5DC5242F45404DCF184AD1C451C009ED83C5242F4540
1073	193	17	\N	\N	0102000020E6100000030000004DCF184AD1C451C009ED83C5242F4540B895254AD1C451C03C060B19262F4540FB832B4AD1C451C0845CAAB6262F4540
1074	193	18	\N	\N	0102000020E610000002000000FB832B4AD1C451C0845CAAB6262F4540DAF7304AD1C451C060D49447272F4540
1075	193	20	\N	\N	0102000020E610000002000000DAF7304AD1C451C060D49447272F454047F9304AD1C451C021BBBA47272F4540
1076	193	22	\N	\N	0102000020E61000000200000047F9304AD1C451C021BBBA47272F4540A5FA304AD1C451C0F21ADF47272F4540
1077	195	9	\N	\N	0102000020E610000002000000DA08B931D2C451C0B5480FB3242F45400C855A3AD2C451C0D0B8DABF242F4540
1078	195	11	\N	\N	0102000020E6100000020000000C855A3AD2C451C0D0B8DABF242F4540D7059E4AD2C451C0C8E1F6D7242F4540
1079	195	13	\N	\N	0102000020E610000003000000D7059E4AD2C451C0C8E1F6D7242F454073E96D55D2C451C0591FFEE7242F45400E6A3DE2D2C451C00376BCB8252F4540
1080	195	16	\N	\N	0102000020E6100000020000000E6A3DE2D2C451C00376BCB8252F45402A501F4CD3C451C0A263B355262F4540
1081	195	17	\N	\N	0102000020E6100000020000002A501F4CD3C451C0A263B355262F4540C9A1264CD3C451C02E36F016272F4540
1082	195	18	\N	\N	0102000020E610000002000000C9A1264CD3C451C02E36F016272F4540122F0A6DD3C451C0F7B0B147272F4540
1083	196	10	\N	\N	0102000020E6100000040000001A1A2E75D3C451C0EB6EA88B272F4540DC933975D3C451C077837CBA282F4540F0B03A75D3C451C0FA63DFD7282F454057ABDD60D3C451C0C92916F6282F4540
1084	196	18	\N	\N	0102000020E61000000200000057ABDD60D3C451C0C92916F6282F45405F42EA60D3C451C07C4A68422A2F4540
1085	196	19	\N	\N	0102000020E6100000020000005F42EA60D3C451C07C4A68422A2F4540C543EA60D3C451C011388D422A2F4540
1086	196	20	\N	\N	0102000020E610000002000000C543EA60D3C451C011388D422A2F45406844EA60D3C451C051029E422A2F4540
1087	197	8	\N	\N	0102000020E610000002000000BBFB2B75D3C451C055D5BF53272F45405A392C75D3C451C04AEC195A272F4540
1088	197	10	\N	\N	0102000020E6100000020000005A392C75D3C451C04AEC195A272F4540CD152E75D3C451C053F5368B272F4540
1089	197	12	\N	\N	0102000020E610000002000000CD152E75D3C451C053F5368B272F454043172E75D3C451C006745D8B272F4540
1090	197	14	\N	\N	0102000020E61000000200000043172E75D3C451C006745D8B272F4540A9182E75D3C451C0E366828B272F4540
1091	197	16	\N	\N	0102000020E610000002000000A9182E75D3C451C0E366828B272F45401A1A2E75D3C451C0EB6EA88B272F4540
1092	198	15	\N	\N	0102000020E61000000200000071DE4C7DD3C451C00656B047272F4540937550A0D3C451C0C3ACBC13272F4540
1093	198	16	\N	\N	0102000020E610000002000000937550A0D3C451C0C3ACBC13272F454065AB4EDFD3C451C07A8745B6262F4540
1094	198	30	\N	\N	0102000020E61000000200000065AB4EDFD3C451C07A8745B6262F4540BD191FF3D3C451C014E043B6262F4540
1095	200	28	\N	\N	0102000020E6100000030000002852BA54CAC451C02FD0F64D0B2F45402630AF54CAC451C07CB8221F0A2F45408E75AC54CAC451C0410EE8D4092F4540
1096	200	30	\N	\N	0102000020E6100000020000008E75AC54CAC451C0410EE8D4092F4540C294A754CAC451C058253750092F4540
1097	200	31	\N	\N	0102000020E610000002000000C294A754CAC451C058253750092F4540E45B447CC9C451C0CBB76C0F082F4540
1098	200	34	\N	\N	0102000020E610000002000000E45B447CC9C451C0CBB76C0F082F4540E67F107CC9C451C082AEBC88022F4540
1099	200	35	\N	\N	0102000020E610000002000000E67F107CC9C451C082AEBC88022F45404A72077CC9C451C02AE1C591012F4540
1100	200	38	\N	\N	0102000020E6100000020000004A72077CC9C451C02AE1C591012F45408A71077CC9C451C06E7FB191012F4540
1101	200	40	\N	\N	0102000020E6100000020000008A71077CC9C451C06E7FB191012F45403771077CC9C451C0CCA1A891012F4540
1102	200	42	\N	\N	0102000020E6100000020000003771077CC9C451C0CCA1A891012F454057A4007CC9C451C0BEB326D8002F4540
1103	200	43	\N	\N	0102000020E61000000200000057A4007CC9C451C0BEB326D8002F4540082E007CC9C451C021568BCB002F4540
1104	200	44	\N	\N	0102000020E610000002000000082E007CC9C451C021568BCB002F45402948F87BC9C451C0F12118F4FF2E4540
1105	200	47	\N	\N	0102000020E6100000020000002948F87BC9C451C0F12118F4FF2E4540B1E5E27BC9C451C03C4EBCACFD2E4540
1106	200	50	\N	\N	0102000020E610000002000000B1E5E27BC9C451C03C4EBCACFD2E45406211E27BC9C451C063B81C96FD2E4540
1107	200	51	\N	\N	0102000020E6100000030000006211E27BC9C451C063B81C96FD2E45407871DF7BC9C451C07E56834EFD2E45401B4BDF7BC9C451C021C36C4AFD2E4540
1108	200	52	\N	\N	0102000020E6100000020000001B4BDF7BC9C451C021C36C4AFD2E45407A4FDB7BC9C451C06BD6C5DDFC2E4540
1109	200	53	\N	\N	0102000020E6100000020000007A4FDB7BC9C451C06BD6C5DDFC2E4540FDD6CE7BC9C451C02F4B9489FB2E4540
1110	200	55	\N	\N	0102000020E610000002000000FDD6CE7BC9C451C02F4B9489FB2E4540AFD6CE7BC9C451C001FA8B89FB2E4540
1111	200	56	\N	\N	0102000020E610000002000000AFD6CE7BC9C451C001FA8B89FB2E454056D5CE7BC9C451C0332E6789FB2E4540
1112	202	9	\N	\N	0102000020E61000000200000094F5FF54CAC451C0C05235B4122F4540D3F4FF54CAC451C073C820B4122F4540
1113	202	11	\N	\N	0102000020E610000002000000D3F4FF54CAC451C073C820B4122F45405822E554CAC451C0DAD388DA0F2F4540
1114	202	12	\N	\N	0102000020E6100000020000005822E554CAC451C0DAD388DA0F2F4540E335D254CAC451C06C09CAD70D2F4540
1115	202	13	\N	\N	0102000020E610000002000000E335D254CAC451C06C09CAD70D2F45402E35D254CAC451C022D8B6D70D2F4540
1116	202	15	\N	\N	0102000020E6100000020000002E35D254CAC451C022D8B6D70D2F45405034D254CAC451C090479FD70D2F4540
1117	202	18	\N	\N	0102000020E6100000030000005034D254CAC451C090479FD70D2F4540A201CB54CAC451C0AC49D4130D2F45409DDFBF54CAC451C0253200E50B2F4540
1118	203	6	\N	\N	0102000020E61000000200000056D5CE7BC9C451C0332E6789FB2E4540D252CD7BC9C451C0DA313760FB2E4540
1119	203	9	\N	\N	0102000020E610000003000000D252CD7BC9C451C0DA313760FB2E454039A1A87BC9C451C0EBCB0060FB2E4540501DB320C7C451C0152F3160FB2E4540
1120	203	12	\N	\N	0102000020E610000002000000501DB320C7C451C0152F3160FB2E45401BC7F5B2C6C451C091FD3960FB2E4540
1121	204	9	\N	\N	0102000020E6100000040000000CE0242BCCC451C06F822F89FB2E45406AE206F9CCC451C072BC1E89FB2E4540CC0B48F9CCC451C0480DBE88FB2E4540E701FF45CDC451C052CAB788FB2E4540
1122	204	17	\N	\N	0102000020E610000002000000E701FF45CDC451C052CAB788FB2E4540A2B4ECE7CDC451C068627498FA2E4540
1123	204	18	\N	\N	0102000020E610000002000000A2B4ECE7CDC451C068627498FA2E4540B7EC8DF1CDC451C044962A8AFA2E4540
1124	206	6	\N	\N	0102000020E61000000200000056D5CE7BC9C451C0332E6789FB2E4540EACD6854CAC451C020AF5589FB2E4540
1125	206	7	\N	\N	0102000020E610000002000000EACD6854CAC451C020AF5589FB2E45408E4E6B54CAC451C0ECAE5589FB2E4540
1126	206	9	\N	\N	0102000020E6100000020000008E4E6B54CAC451C0ECAE5589FB2E45409F308854CAC451C097AC5589FB2E4540
1127	206	12	\N	\N	0102000020E6100000030000009F308854CAC451C097AC5589FB2E454087BABD90CAC451C088CF5089FB2E4540F30CD9ABCBC451C09DDB3989FB2E4540
1128	207	10	\N	\N	0102000020E610000002000000B7EC8DF1CDC451C044962A8AFA2E4540EB05D238D0C451C0F385FA89FA2E4540
1129	207	11	\N	\N	0102000020E610000005000000EB05D238D0C451C0F385FA89FA2E45408A39050DD2C451C003F1D389FA2E4540AFA9589FD2C451C03D97C062FB2E4540626F13C3D2C451C0C99EBD62FB2E454046ADBBC1D3C451C0724043DCFC2E4540
1130	207	20	\N	\N	0102000020E61000000200000046ADBBC1D3C451C0724043DCFC2E4540DFE707D1D3C451C0B0F941DCFC2E4540
1131	208	3	\N	\N	0102000020E610000002000000B7EC8DF1CDC451C044962A8AFA2E454067CD4709CDC451C0A8D4D231F92E4540
1132	208	4	\N	\N	0102000020E61000000200000067CD4709CDC451C0A8D4D231F92E4540744A22B7CCC451C07FE00AB8F82E4540
1133	208	6	\N	\N	0102000020E610000002000000744A22B7CCC451C07FE00AB8F82E4540534755AACCC451C0ACC010A5F82E4540
1134	209	44	\N	\N	0102000020E6100000020000009DF7751FC9C451C0334D4EB4122F4540E711C4EAC8C451C080C52F66122F4540
1135	209	46	\N	\N	0102000020E610000002000000E711C4EAC8C451C080C52F66122F4540C29F80DAC8C451C0B389134E122F4540
1136	209	48	\N	\N	0102000020E610000002000000C29F80DAC8C451C0B389134E122F4540CCD81446C8C451C0567B0B72112F4540
1137	209	50	\N	\N	0102000020E610000002000000CCD81446C8C451C0567B0B72112F45403F3E633CC8C451C0868CAC63112F4540
1138	209	53	\N	\N	0102000020E6100000020000003F3E633CC8C451C0868CAC63112F4540CEE30538C8C451C0C017345D112F4540
1139	209	54	\N	\N	0102000020E610000002000000CEE30538C8C451C0C017345D112F4540ADA1F021C8C451C0313D773C112F4540
1140	209	56	\N	\N	0102000020E610000002000000ADA1F021C8C451C0313D773C112F4540769D9DDAC7C451C05C93BAD2102F4540
1141	209	58	\N	\N	0102000020E610000002000000769D9DDAC7C451C05C93BAD2102F454075A8BD91C7C451C07774B166102F4540
1142	209	60	\N	\N	0102000020E61000000200000075A8BD91C7C451C07774B166102F454039397A81C7C451C0F93C954E102F4540
1143	209	62	\N	\N	0102000020E61000000200000039397A81C7C451C0F93C954E102F4540F5F35CE3C6C451C0AC692E640F2F4540
1144	209	65	\N	\N	0102000020E610000002000000F5F35CE3C6C451C0AC692E640F2F4540E61DC9E1C6C451C0A1BBD7610F2F4540
1145	209	66	\N	\N	0102000020E610000002000000E61DC9E1C6C451C0A1BBD7610F2F45407165FAD9C6C451C06AAA44560F2F4540
1146	209	67	\N	\N	0102000020E6100000020000007165FAD9C6C451C06AAA44560F2F454047692C45C6C451C0AC04AB790E2F4540
1147	209	69	\N	\N	0102000020E61000000200000047692C45C6C451C0AC04AB790E2F45406414013FC6C451C006B085700E2F4540
1148	209	72	\N	\N	0102000020E6100000020000006414013FC6C451C006B085700E2F4540D7FCE834C6C451C054D18E610E2F4540
1149	209	74	\N	\N	0102000020E610000002000000D7FCE834C6C451C054D18E610E2F454060EA3EB7C5C451C0B84343A70D2F4540
1150	209	86	\N	\N	0102000020E61000000200000060EA3EB7C5C451C0B84343A70D2F4540BE7E38B7C5C451C0DAA7DBF50C2F4540
1151	209	87	\N	\N	0102000020E610000002000000BE7E38B7C5C451C0DAA7DBF50C2F4540F8EAD7B6C5C451C011A94E89022F4540
1152	209	88	\N	\N	0102000020E610000002000000F8EAD7B6C5C451C011A94E89022F4540B8FACEB6C5C451C03A695392012F4540
1153	210	12	\N	\N	0102000020E6100000030000000C89F803C4C451C09EEC7592012F45402B00DDE8C2C451C054498C92012F4540C1964DDCC2C451C0E4DD2FA5012F4540
1154	210	21	\N	\N	0102000020E610000002000000C1964DDCC2C451C0E4DD2FA5012F454025D752CEC2C451C0E6327790012F4540
1155	210	24	\N	\N	0102000020E61000000200000025D752CEC2C451C0E6327790012F4540C6947B2FC0C451C0DD5819AEFD2E4540
1156	214	5	\N	\N	0102000020E610000002000000C6947B2FC0C451C0DD5819AEFD2E4540DC63B1A4BFC451C0D490067CFE2E4540
1157	214	8	\N	\N	0102000020E610000003000000DC63B1A4BFC451C0D490067CFE2E45406D678C7EBFC451C0C989097CFE2E454068FD0180BEC451C002CDB4F5FF2E4540
1158	214	10	\N	\N	0102000020E61000000200000068FD0180BEC451C002CDB4F5FF2E45407D89FB7ABEC451C0E030B5F5FF2E4540
1159	215	6	\N	\N	0102000020E6100000020000007D89FB7ABEC451C0E030B5F5FF2E4540FC107ADDBDC451C0DC1567DF002F4540
1160	215	7	\N	\N	0102000020E610000002000000FC107ADDBDC451C0DC1567DF002F4540FDF888BDBCC451C057E6A08A022F4540
1161	215	12	\N	\N	0102000020E610000002000000FDF888BDBCC451C057E6A08A022F454061BDAE69BCC451C0A45DA78A022F4540
1162	216	4	\N	\N	0102000020E6100000020000007D89FB7ABEC451C0E030B5F5FF2E4540F1B29C77BDC451C053DF2F75FE2E4540
1163	216	5	\N	\N	0102000020E610000002000000F1B29C77BDC451C053DF2F75FE2E454038DF516DBDC451C030B3ED65FE2E4540
1164	216	8	\N	\N	0102000020E61000000300000038DF516DBDC451C030B3ED65FE2E4540C40A5BAFBCC451C06BBB4D4CFD2E45403A65ACA7BCC451C020534E4CFD2E4540
1165	217	4	\N	\N	0102000020E610000002000000B8FACEB6C5C451C03A695392012F454000FACEB6C5C451C0A5983F92012F4540
1166	217	5	\N	\N	0102000020E61000000200000000FACEB6C5C451C0A5983F92012F4540B1F9CEB6C5C451C0EFF93692012F4540
1167	217	7	\N	\N	0102000020E610000002000000B1F9CEB6C5C451C0EFF93692012F4540CB42C8B6C5C451C07D34AFD8002F4540
1168	217	8	\N	\N	0102000020E610000002000000CB42C8B6C5C451C07D34AFD8002F45402DCEC7B6C5C451C02DDE18CC002F4540
1169	218	19	\N	\N	0102000020E610000002000000874E2B21C7C451C0F0B218C7122F454069927E68C7C451C0E9ADD530132F4540
1170	218	21	\N	\N	0102000020E61000000200000069927E68C7C451C0E9ADD530132F454038C8A28CC7C451C066E36966132F4540
1171	218	23	\N	\N	0102000020E61000000200000038C8A28CC7C451C066E36966132F45408892481BC8C451C07BC0E239142F4540
1172	218	38	\N	\N	0102000020E6100000020000008892481BC8C451C07BC0E239142F4540F4B9951BC8C451C08B12667C1C2F4540
1173	219	35	\N	\N	0102000020E61000000200000068E40B56BBC451C034E9DEB8152F4540A12AD9EABAC451C0CDB7EB57162F4540
1174	219	36	\N	\N	0102000020E610000002000000A12AD9EABAC451C0CDB7EB57162F4540A21C1D0FBAC451C08BF6F09D172F4540
1175	219	54	\N	\N	0102000020E610000002000000A21C1D0FBAC451C08BF6F09D172F454046543F0FBAC451C03CD9B0761B2F4540
1176	219	60	\N	\N	0102000020E61000000200000046543F0FBAC451C03CD9B0761B2F45409F43E2C2B9C451C0A3B7FDE71B2F4540
1177	219	70	\N	\N	0102000020E6100000020000009F43E2C2B9C451C0A3B7FDE71B2F45405CBEE7C2B9C451C03562DA851C2F4540
1178	220	15	\N	\N	0102000020E6100000020000001C4579E0BBC451C0D0E1B0851C2F4540BDE32E6ABCC451C0C744A6851C2F4540
1179	220	16	\N	\N	0102000020E610000002000000BDE32E6ABCC451C0C744A6851C2F4540B06846A8BCC451C0B27BA1851C2F4540
1180	220	17	\N	\N	0102000020E610000003000000B06846A8BCC451C0B27BA1851C2F4540C9BF95FBBCC451C0F90F9B851C2F4540A1BD5F7ABDC451C0524391851C2F4540
1181	220	27	\N	\N	0102000020E610000002000000A1BD5F7ABDC451C0524391851C2F45409AC76311BEC451C0587D72651D2F4540
1182	220	28	\N	\N	0102000020E6100000020000009AC76311BEC451C0587D72651D2F4540D6BE323FBEC451C090A15BA91D2F4540
1183	220	30	\N	\N	0102000020E610000002000000D6BE323FBEC451C090A15BA91D2F45402AD14067BEC451C0BA37BDE41D2F4540
1184	222	2	\N	\N	0102000020E6100000030000005CBEE7C2B9C451C03562DA851C2F45406ADE2940BAC451C004D0D0851C2F4540EA3D2D56BBC451C04E82BB851C2F4540
1185	222	4	\N	\N	0102000020E610000002000000EA3D2D56BBC451C04E82BB851C2F45401959465BBBC451C04C1EBB851C2F4540
1186	223	23	\N	\N	0102000020E6100000020000002AD14067BEC451C0BA37BDE41D2F4540B306917BBEC451C0F2A1BBE41D2F4540
1187	223	26	\N	\N	0102000020E610000002000000B306917BBEC451C0F2A1BBE41D2F4540118CBBF5BEC451C08E19B2E41D2F4540
1188	223	29	\N	\N	0102000020E610000002000000118CBBF5BEC451C08E19B2E41D2F4540BF04C6F5BEC451C0BC18B2E41D2F4540
1189	223	31	\N	\N	0102000020E610000002000000BF04C6F5BEC451C0BC18B2E41D2F45407A18C7F5BEC451C0A718B2E41D2F4540
1190	223	33	\N	\N	0102000020E6100000020000007A18C7F5BEC451C0A718B2E41D2F4540A81BD2F5BEC451C0CB17B2E41D2F4540
1191	223	34	\N	\N	0102000020E610000002000000A81BD2F5BEC451C0CB17B2E41D2F454020C71B30C0C451C0929199E41D2F4540
1192	223	35	\N	\N	0102000020E61000000200000020C71B30C0C451C0929199E41D2F4540DE731C30C0C451C0849199E41D2F4540
1193	223	38	\N	\N	0102000020E610000002000000DE731C30C0C451C0849199E41D2F45407E24630CC1C451C0466188E41D2F4540
1194	223	41	\N	\N	0102000020E6100000020000007E24630CC1C451C0466188E41D2F4540F1C86D0CC1C451C0716088E41D2F4540
1195	223	43	\N	\N	0102000020E610000002000000F1C86D0CC1C451C0716088E41D2F45402DE16E0CC1C451C05B6088E41D2F4540
1196	223	45	\N	\N	0102000020E6100000020000002DE16E0CC1C451C05B6088E41D2F454064127A0CC1C451C07C5F88E41D2F4540
1197	223	46	\N	\N	0102000020E61000000200000064127A0CC1C451C07C5F88E41D2F454070FA0E81C1C451C0A5467FE41D2F4540
1198	224	29	\N	\N	0102000020E6100000020000002AD14067BEC451C0BA37BDE41D2F45409A984461BEC451C0E2939EED1D2F4540
1199	224	32	\N	\N	0102000020E6100000020000009A984461BEC451C0E2939EED1D2F4540F21E12F6BDC451C0A50BAB8C1E2F4540
1200	224	33	\N	\N	0102000020E610000002000000F21E12F6BDC451C0A50BAB8C1E2F4540FEBFDE7CBDC451C08D6E7E401F2F4540
1201	224	58	\N	\N	0102000020E610000002000000FEBFDE7CBDC451C08D6E7E401F2F4540CFDEE27CBDC451C0817AA4B51F2F4540
1202	225	14	\N	\N	0102000020E610000002000000CFDEE27CBDC451C0817AA4B51F2F4540AB16F7A2BDC451C06A2118EE1F2F4540
1203	225	25	\N	\N	0102000020E610000004000000AB16F7A2BDC451C06A2118EE1F2F45407FBBFDA2BDC451C087DAE3AA202F4540317C5BA9BDC451C076F253B4202F4540B9007AA9BDC451C03B2A7517242F4540
1204	225	26	\N	\N	0102000020E610000002000000B9007AA9BDC451C03B2A7517242F4540973B7AA9BDC451C06FDBFD1D242F4540
1205	225	27	\N	\N	0102000020E610000003000000973B7AA9BDC451C06FDBFD1D242F45406F2B7CA9BDC451C003B90655242F45402AB914EDBDC451C091823CB9242F4540
1206	225	28	\N	\N	0102000020E6100000020000002AB914EDBDC451C091823CB9242F454067A72CF7BDC451C0C12733C8242F4540
1207	226	3	\N	\N	0102000020E61000000200000067A72CF7BDC451C0C12733C8242F4540DE096367BEC451C0DE712AC8242F4540
1208	226	6	\N	\N	0102000020E610000002000000DE096367BEC451C0DE712AC8242F4540A3F2DDF5BEC451C081621FC8242F4540
1209	227	4	\N	\N	0102000020E610000002000000A3F2DDF5BEC451C081621FC8242F4540C070E8F5BEC451C0B0611FC8242F4540
1210	227	5	\N	\N	0102000020E610000002000000C070E8F5BEC451C0B0611FC8242F45400B85E9F5BEC451C09A611FC8242F4540
1211	227	7	\N	\N	0102000020E6100000020000000B85E9F5BEC451C09A611FC8242F4540F18DF4F5BEC451C0BE601FC8242F4540
1212	227	8	\N	\N	0102000020E610000003000000F18DF4F5BEC451C0BE601FC8242F4540DABE3101C0C451C02A8F0AC8242F4540108B850CC1C451C058A8F5C7242F4540
1213	228	22	\N	\N	0102000020E61000000300000068C8DE2FC3C451C009B788A0272F4540DFA5E92FC3C451C0A5CB5CCF282F45405D8BF435C3C451C0210752D8282F4540
1214	228	35	\N	\N	0102000020E6100000020000005D8BF435C3C451C0210752D8282F45403F358D1BC3C451C069E57EFF282F4540
1215	228	41	\N	\N	0102000020E6100000020000003F358D1BC3C451C069E57EFF282F45407F43991BC3C451C08A53994F2A2F4540
1216	228	42	\N	\N	0102000020E6100000020000007F43991BC3C451C08A53994F2A2F45401C89991BC3C451C0B42A2E572A2F4540
1217	228	43	\N	\N	0102000020E6100000020000001C89991BC3C451C0B42A2E572A2F45405E8A991BC3C451C04C2651572A2F4540
1218	228	44	\N	\N	0102000020E6100000020000005E8A991BC3C451C04C2651572A2F45407DF5991BC3C451C0DAA7FB622A2F4540
1219	229	14	\N	\N	0102000020E6100000020000002358DC2FC3C451C09A4B915C272F4540831ADE2FC3C451C0E5FB998D272F4540
1220	229	16	\N	\N	0102000020E610000002000000831ADE2FC3C451C0E5FB998D272F4540BC1BDE2FC3C451C04706BC8D272F4540
1221	229	18	\N	\N	0102000020E610000002000000BC1BDE2FC3C451C04706BC8D272F4540E71CDE2FC3C451C076A9DC8D272F4540
1222	229	20	\N	\N	0102000020E610000002000000E71CDE2FC3C451C076A9DC8D272F45401C1EDE2FC3C451C0DB37FE8D272F4540
1223	229	22	\N	\N	0102000020E6100000020000001C1EDE2FC3C451C0DB37FE8D272F4540A8C4DE2FC3C451C08F2B20A0272F4540
1224	229	24	\N	\N	0102000020E610000002000000A8C4DE2FC3C451C08F2B20A0272F4540E0C5DE2FC3C451C0B53242A0272F4540
1225	229	26	\N	\N	0102000020E610000002000000E0C5DE2FC3C451C0B53242A0272F454022C7DE2FC3C451C0B13365A0272F4540
1226	229	28	\N	\N	0102000020E61000000200000022C7DE2FC3C451C0B13365A0272F454068C8DE2FC3C451C009B788A0272F4540
1227	230	46	\N	\N	0102000020E610000002000000108B850CC1C451C058A8F5C7242F4540E11C900CC1C451C084A7F5C7242F4540
1228	230	47	\N	\N	0102000020E610000002000000E11C900CC1C451C084A7F5C7242F45403233910CC1C451C06EA7F5C7242F4540
1229	230	49	\N	\N	0102000020E6100000020000003233910CC1C451C06EA7F5C7242F4540BA923181C1C451C08B80ECC7242F4540
1230	230	50	\N	\N	0102000020E610000003000000BA923181C1C451C08B80ECC7242F45404457D917C2C451C00EAEE0C7242F4540E39F7F4AC2C451C05EB2DCC7242F4540
1231	230	57	\N	\N	0102000020E610000002000000E39F7F4AC2C451C05EB2DCC7242F4540D1DD6060C2C451C00E684CE8242F4540
1232	230	60	\N	\N	0102000020E610000002000000D1DD6060C2C451C00E684CE8242F45405A6D2128C3C451C073286D10262F4540
1233	230	63	\N	\N	0102000020E6100000020000005A6D2128C3C451C073286D10262F454017D6D02FC3C451C0BFCBD11B262F4540
1234	230	78	\N	\N	0102000020E61000000300000017D6D02FC3C451C0BFCBD11B262F4540AE7AD12FC3C451C0D836BD2D262F4540C276D62FC3C451C095BCABB8262F4540
1235	230	79	\N	\N	0102000020E610000002000000C276D62FC3C451C095BCABB8262F45403EAADB2FC3C451C01F90A249272F4540
1236	230	81	\N	\N	0102000020E6100000020000003EAADB2FC3C451C01F90A249272F454077ABDB2FC3C451C06A9AC449272F4540
1237	230	83	\N	\N	0102000020E61000000200000077ABDB2FC3C451C06A9AC449272F4540A3ACDB2FC3C451C0873DE549272F4540
1238	230	85	\N	\N	0102000020E610000002000000A3ACDB2FC3C451C0873DE549272F4540D2ADDB2FC3C451C09A4E064A272F4540
1239	230	87	\N	\N	0102000020E610000002000000D2ADDB2FC3C451C09A4E064A272F4540DBADDB2FC3C451C01049074A272F4540
1240	230	89	\N	\N	0102000020E610000002000000DBADDB2FC3C451C01049074A272F4540971CDC2FC3C451C0AC9D1556272F4540
1241	230	92	\N	\N	0102000020E610000002000000971CDC2FC3C451C0AC9D1556272F45402358DC2FC3C451C09A4B915C272F4540
1242	231	15	\N	\N	0102000020E610000002000000177F9F0CC1C451C078BDB3A0272F454055809F0CC1C451C05BACD6A0272F4540
1243	231	17	\N	\N	0102000020E61000000300000055809F0CC1C451C05BACD6A0272F45400548AA0CC1C451C016D287CF282F45403E55C820C1C451C01AA85AED282F4540
1244	231	28	\N	\N	0102000020E6100000030000003E55C820C1C451C01AA85AED282F4540F267AC0CC1C451C0E0A4300B292F45405DF8B70CC1C451C04704E64F2A2F4540
1245	231	29	\N	\N	0102000020E6100000020000005DF8B70CC1C451C04704E64F2A2F4540773DB80CC1C451C0824E7A572A2F4540
1246	231	30	\N	\N	0102000020E610000002000000773DB80CC1C451C0824E7A572A2F4540B13EB80CC1C451C07BBE9C572A2F4540
1247	232	12	\N	\N	0102000020E6100000020000006E139D0CC1C451C00A52BC5C272F4540AC149D0CC1C451C0EC40DF5C272F4540
1248	232	14	\N	\N	0102000020E610000002000000AC149D0CC1C451C0EC40DF5C272F4540A1D39E0CC1C451C0B844E58D272F4540
1249	232	16	\N	\N	0102000020E610000002000000A1D39E0CC1C451C0B844E58D272F4540D2D49E0CC1C451C040B9068E272F4540
1250	232	18	\N	\N	0102000020E610000002000000D2D49E0CC1C451C040B9068E272F4540F6D59E0CC1C451C065CB268E272F4540
1251	232	20	\N	\N	0102000020E610000002000000F6D59E0CC1C451C065CB268E272F4540AC7C9F0CC1C451C02DD26FA0272F4540
1252	232	22	\N	\N	0102000020E610000002000000AC7C9F0CC1C451C02DD26FA0272F4540DD7D9F0CC1C451C0864D91A0272F4540
1253	232	24	\N	\N	0102000020E610000002000000DD7D9F0CC1C451C0864D91A0272F4540177F9F0CC1C451C078BDB3A0272F4540
1254	233	10	\N	\N	0102000020E610000003000000108B850CC1C451C058A8F5C7242F4540824A920CC1C451C0443DE82D262F4540F8679C0CC1C451C0F5D8ED49272F4540
1255	233	12	\N	\N	0102000020E610000002000000F8679C0CC1C451C0F5D8ED49272F454029699C0CC1C451C06A4D0F4A272F4540
1256	233	14	\N	\N	0102000020E61000000200000029699C0CC1C451C06A4D0F4A272F45404D6A9C0CC1C451C0815F2F4A272F4540
1257	233	16	\N	\N	0102000020E6100000020000004D6A9C0CC1C451C0815F2F4A272F454003119D0CC1C451C0DE66785C272F4540
1258	233	18	\N	\N	0102000020E61000000200000003119D0CC1C451C0DE66785C272F454034129D0CC1C451C029E2995C272F4540
1259	233	20	\N	\N	0102000020E61000000200000034129D0CC1C451C029E2995C272F45406E139D0CC1C451C00A52BC5C272F4540
1260	234	13	\N	\N	0102000020E61000000200000064B6F7F5BEC451C0A477DDA0272F454097B7F7F5BEC451C0E659FFA0272F4540
1261	234	15	\N	\N	0102000020E61000000300000097B7F7F5BEC451C0E659FFA0272F4540426B02F6BEC451C0468CB1CF282F45408176200ABFC451C03A6584ED282F4540
1262	234	25	\N	\N	0102000020E6100000030000008176200ABFC451C03A6584ED282F45403B8704F6BEC451C00F5F5A0B292F4540610310F6BEC451C071BD32502A2F4540
1263	234	26	\N	\N	0102000020E610000002000000610310F6BEC451C071BD32502A2F4540F54710F6BEC451C0AF78C6572A2F4540
1264	235	10	\N	\N	0102000020E6100000020000003C4FF5F5BEC451C0380CE65C272F45406F50F5F5BEC451C070EE075D272F4540
1265	235	12	\N	\N	0102000020E6100000020000006F50F5F5BEC451C070EE075D272F4540A651F5F5BEC451C0434C2A5D272F4540
1266	235	14	\N	\N	0102000020E610000002000000A651F5F5BEC451C0434C2A5D272F4540430DF7F5BEC451C03AB32D8E272F4540
1267	235	16	\N	\N	0102000020E610000002000000430DF7F5BEC451C03AB32D8E272F45406C0EF7F5BEC451C055954E8E272F4540
1268	235	18	\N	\N	0102000020E6100000020000006C0EF7F5BEC451C055954E8E272F45403AB5F7F5BEC451C0E584BCA0272F4540
1269	235	20	\N	\N	0102000020E6100000020000003AB5F7F5BEC451C0E584BCA0272F454064B6F7F5BEC451C0A477DDA0272F4540
1270	236	8	\N	\N	0102000020E610000002000000A3F2DDF5BEC451C081621FC8242F4540D6F3DDF5BEC451C0B04441C8242F4540
1271	236	10	\N	\N	0102000020E610000003000000D6F3DDF5BEC451C0B04441C8242F45405F9AEAF5BEC451C071F7112E262F45401BA6F4F5BEC451C0D247364A272F4540
1272	236	12	\N	\N	0102000020E6100000020000001BA6F4F5BEC451C0D247364A272F454044A7F4F5BEC451C0EB29574A272F4540
1273	236	14	\N	\N	0102000020E61000000200000044A7F4F5BEC451C0EB29574A272F4540124EF5F5BEC451C07719C55C272F4540
1274	236	16	\N	\N	0102000020E610000002000000124EF5F5BEC451C07719C55C272F45403C4FF5F5BEC451C0380CE65C272F4540
1275	237	11	\N	\N	0102000020E61000000200000005029EF2BCC451C0636605A1272F454028039EF2BCC451C082D525A1272F4540
1276	237	13	\N	\N	0102000020E61000000200000028039EF2BCC451C082D525A1272F454054049EF2BCC451C02F2F47A1272F4540
1277	237	15	\N	\N	0102000020E61000000200000054049EF2BCC451C02F2F47A1272F454084059EF2BCC451C03F0169A1272F4540
1278	237	17	\N	\N	0102000020E61000000500000084059EF2BCC451C03F0169A1272F45406C3FA5F2BCC451C09282406F282F4540965C12ECBCC451C084650179282F4540016915ECBCC451C0FBFCD9CF282F454030B0D5F9BCC451C0A4C03CE4282F4540
1279	237	22	\N	\N	0102000020E61000000300000030B0D5F9BCC451C0A4C03CE4282F4540224858DABCC451C00867F512292F4540E86C63DABCC451C0A10F7F502A2F4540
1280	238	8	\N	\N	0102000020E610000002000000349F9BF2BCC451C0F5FA0D5D272F454057A09BF2BCC451C0156A2E5D272F4540
1281	238	10	\N	\N	0102000020E61000000200000057A09BF2BCC451C0156A2E5D272F454083A19BF2BCC451C0BEC34F5D272F4540
1282	238	12	\N	\N	0102000020E61000000200000083A19BF2BCC451C0BEC34F5D272F4540B3A29BF2BCC451C0CC95715D272F4540
1283	238	14	\N	\N	0102000020E610000002000000B3A29BF2BCC451C0CC95715D272F4540185B9DF2BCC451C04A78728E272F4540
1284	238	16	\N	\N	0102000020E610000002000000185B9DF2BCC451C04A78728E272F454005029EF2BCC451C0636605A1272F4540
1285	239	24	\N	\N	0102000020E61000000200000067A72CF7BDC451C0C12733C8242F4540DF6D2FEDBDC451C0E54D05D7242F4540
1286	239	26	\N	\N	0102000020E610000003000000DF6D2FEDBDC451C0E54D05D7242F454066CF8AEABDC451C0D933F1DA242F4540117AF7A3BDC451C072A3A743252F4540
1287	239	27	\N	\N	0102000020E610000002000000117AF7A3BDC451C072A3A743252F4540EFEDD23ABDC451C0E79EA7DF252F4540
1288	239	30	\N	\N	0102000020E610000002000000EFEDD23ABDC451C0E79EA7DF252F4540EE16EFF8BCC451C0635F6A41262F4540
1289	239	48	\N	\N	0102000020E610000004000000EE16EFF8BCC451C0635F6A41262F4540297DF5F8BCC451C0972AB0F7262F4540126598F2BCC451C06F3E2101272F4540349F9BF2BCC451C0F5FA0D5D272F4540
1290	240	8	\N	\N	0102000020E610000002000000CFDEE27CBDC451C0817AA4B51F2F45405F84CB3DBDC451C0693C4013202F4540
1291	240	9	\N	\N	0102000020E6100000020000005F84CB3DBDC451C0693C4013202F4540913F6139BDC451C02337CD19202F4540
1292	240	12	\N	\N	0102000020E610000002000000913F6139BDC451C02337CD19202F4540AD751736BDC451C04A2DAE1E202F4540
1293	240	14	\N	\N	0102000020E610000002000000AD751736BDC451C04A2DAE1E202F4540228C2AE0BCC451C001FD2A9E202F4540
1294	240	16	\N	\N	0102000020E610000002000000228C2AE0BCC451C001FD2A9E202F4540C5F931DFBCC451C04ACB9B9F202F4540
1295	241	7	\N	\N	0102000020E6100000020000005CBEE7C2B9C451C03562DA851C2F45403EBFE7C2B9C451C033D1F3851C2F4540
1296	241	8	\N	\N	0102000020E6100000020000003EBFE7C2B9C451C033D1F3851C2F454087BFE7C2B9C451C01313FC851C2F4540
1297	241	10	\N	\N	0102000020E61000000200000087BFE7C2B9C451C01313FC851C2F454005F2F3C2B9C451C0213462E51D2F4540
1298	241	13	\N	\N	0102000020E61000000200000005F2F3C2B9C451C0213462E51D2F4540B2F3F3C2B9C451C0B47992E51D2F4540
1299	241	14	\N	\N	0102000020E610000002000000B2F3F3C2B9C451C0B47992E51D2F45403C21F7C2B9C451C0685120411E2F4540
1300	242	33	\N	\N	0102000020E610000004000000D4DFB3B5B3C451C004F5EE1A192F4540823EBEB5B3C451C05468484C1A2F4540289D28BAB3C451C00E33D4521A2F45401B0F2CBAB3C451C0044344B81A2F4540
1301	242	34	\N	\N	0102000020E6100000020000001B0F2CBAB3C451C0044344B81A2F454078FE1791B4C451C00223E4F61B2F4540
1302	242	37	\N	\N	0102000020E61000000300000078FE1791B4C451C00223E4F61B2F454088D92491B4C451C00C3D42701D2F45409D3F0000B5C451C054089B141E2F4540
1303	242	45	\N	\N	0102000020E6100000020000009D3F0000B5C451C054089B141E2F45402CCA0100B5C451C03EAFC6411E2F4540
1304	242	46	\N	\N	0102000020E6100000020000002CCA0100B5C451C03EAFC6411E2F454080840E00B5C451C02608CDB61F2F4540
1305	242	49	\N	\N	0102000020E61000000200000080840E00B5C451C02608CDB61F2F45406F7F1600B5C451C032D2AEA0202F4540
1306	242	50	\N	\N	0102000020E6100000030000006F7F1600B5C451C032D2AEA0202F4540445E2300B5C451C0FE10E319222F4540D34C2F00B5C451C0E9239577232F4540
1307	242	65	\N	\N	0102000020E610000003000000D34C2F00B5C451C0E9239577232F45409027DADDB4C451C0A46A85AA232F4540E0E1DDDDB4C451C076CFD317242F4540
1308	242	66	\N	\N	0102000020E610000002000000E0E1DDDDB4C451C076CFD317242F454075E9DDDDB4C451C00C23B218242F4540
1309	243	6	\N	\N	0102000020E6100000020000005B16B1B5B3C451C0A8FADDC8182F4540D8D6B3B5B3C451C0F55DE619192F4540
1310	243	8	\N	\N	0102000020E610000002000000D8D6B3B5B3C451C0F55DE619192F454012DCB3B5B3C451C0E24A801A192F4540
1311	243	10	\N	\N	0102000020E61000000200000012DCB3B5B3C451C0E24A801A192F45405FDDB3B5B3C451C0959DA61A192F4540
1312	243	12	\N	\N	0102000020E6100000020000005FDDB3B5B3C451C0959DA61A192F4540D4DFB3B5B3C451C004F5EE1A192F4540
1313	244	27	\N	\N	0102000020E61000000200000065C412ECB4C451C00BA96458152F45400E1CDC0EB4C451C001E39AA0162F4540
1314	244	28	\N	\N	0102000020E6100000020000000E1CDC0EB4C451C001E39AA0162F4540370C25D5B3C451C0F3773CF6162F4540
1315	244	30	\N	\N	0102000020E610000002000000370C25D5B3C451C0F3773CF6162F4540AC9EB8BEB3C451C0F4788117172F4540
1316	244	32	\N	\N	0102000020E610000002000000AC9EB8BEB3C451C0F4788117172F4540F4D3A2B5B3C451C0D138FC24172F4540
1317	244	48	\N	\N	0102000020E610000002000000F4D3A2B5B3C451C0D138FC24172F45405F0DB1B5B3C451C02F63D5C7182F4540
1318	244	50	\N	\N	0102000020E6100000020000005F0DB1B5B3C451C02F63D5C7182F45409912B1B5B3C451C059506FC8182F4540
1319	244	52	\N	\N	0102000020E6100000020000009912B1B5B3C451C059506FC8182F4540E613B1B5B3C451C01CA395C8182F4540
1320	244	54	\N	\N	0102000020E610000002000000E613B1B5B3C451C01CA395C8182F45405B16B1B5B3C451C0A8FADDC8182F4540
1321	245	10	\N	\N	0102000020E6100000020000004AB265D2B1C451C0DD257C8A112F4540D7B065D2B1C451C0F536518A112F4540
1322	245	12	\N	\N	0102000020E610000002000000D7B065D2B1C451C0F536518A112F45406EAA65D2B1C451C0C2129389112F4540
1323	245	14	\N	\N	0102000020E6100000030000006EAA65D2B1C451C0C2129389112F45400D8957D2B1C451C0F1629AE60F2F4540229852D2B1C451C049F718540F2F4540
1324	245	20	\N	\N	0102000020E610000002000000229852D2B1C451C049F718540F2F4540DD9A2369B3C451C0960782F80C2F4540
1325	246	4	\N	\N	0102000020E610000002000000C7DB68D2B1C451C036C83DE8112F454054DA68D2B1C451C048D912E8112F4540
1326	246	6	\N	\N	0102000020E61000000200000054DA68D2B1C451C048D912E8112F4540EBD368D2B1C451C003B554E7112F4540
1327	246	8	\N	\N	0102000020E610000002000000EBD368D2B1C451C003B554E7112F45404AB265D2B1C451C0DD257C8A112F4540
1328	247	16	\N	\N	0102000020E610000002000000FC8C86D2B1C451C07ADC9F58152F4540358C86D2B1C451C016DB8858152F4540
1329	247	18	\N	\N	0102000020E610000002000000358C86D2B1C451C016DB8858152F4540898B86D2B1C451C06EED7458152F4540
1330	247	21	\N	\N	0102000020E610000002000000898B86D2B1C451C06EED7458152F4540F18A86D2B1C451C0694E6358152F4540
1331	247	24	\N	\N	0102000020E610000002000000F18A86D2B1C451C0694E6358152F4540208586D2B1C451C0A2C8B657152F4540
1332	247	27	\N	\N	0102000020E610000002000000208586D2B1C451C0A2C8B657152F4540808486D2B1C451C05042A457152F4540
1333	247	30	\N	\N	0102000020E610000002000000808486D2B1C451C05042A457152F45408F8386D2B1C451C02A678857152F4540
1334	247	31	\N	\N	0102000020E6100000030000008F8386D2B1C451C02A678857152F4540050577D2B1C451C0D58A1F8C132F4540B87870D2B1C451C08E92F8C9122F4540
1335	247	32	\N	\N	0102000020E610000002000000B87870D2B1C451C08E92F8C9122F4540C7DB68D2B1C451C036C83DE8112F4540
1336	248	14	\N	\N	0102000020E610000002000000DD9A2369B3C451C0960782F80C2F454012A72169B3C451C01EDAF4BE0C2F4540
1337	248	17	\N	\N	0102000020E61000000200000012A72169B3C451C01EDAF4BE0C2F4540EF9F2169B3C451C0278322BE0C2F4540
1338	248	20	\N	\N	0102000020E610000002000000EF9F2169B3C451C0278322BE0C2F454084C3E768B3C451C0497F7914062F4540
1339	248	22	\N	\N	0102000020E61000000300000084C3E768B3C451C0497F7914062F454047A4BDC4B3C451C0FEED378C052F454048A2AAC4B3C451C0381BA05C032F4540
1340	248	28	\N	\N	0102000020E61000000300000048A2AAC4B3C451C0381BA05C032F454052AB1BB5B3C451C0923A8F45032F4540987C18B5B3C451C07A34D8E7022F4540
1341	249	22	\N	\N	0102000020E610000002000000DD9A2369B3C451C0960782F80C2F45409E4CEC6FB3C451C0D5B890020D2F4540
1342	249	25	\N	\N	0102000020E6100000020000009E4CEC6FB3C451C0D5B890020D2F4540B907377AB3C451C097C6D2110D2F4540
1343	249	27	\N	\N	0102000020E610000002000000B907377AB3C451C097C6D2110D2F45403F017E7AB3C451C05BFF3B120D2F4540
1344	249	28	\N	\N	0102000020E6100000020000003F017E7AB3C451C05BFF3B120D2F45407B1EDA8DB3C451C0398FEF2E0D2F4540
1345	249	30	\N	\N	0102000020E6100000020000007B1EDA8DB3C451C0398FEF2E0D2F45408E34ED90B3C451C02D6F7E330D2F4540
1346	249	32	\N	\N	0102000020E6100000020000008E34ED90B3C451C02D6F7E330D2F45407A5454E6B3C451C0CD0E1BB20D2F4540
1347	249	33	\N	\N	0102000020E6100000020000007A5454E6B3C451C0CD0E1BB20D2F4540FA829663B4C451C03FF7CD6B0E2F4540
1348	249	36	\N	\N	0102000020E610000002000000FA829663B4C451C03FF7CD6B0E2F45402C600BC4B4C451C07ABFCDFA0E2F4540
1349	249	40	\N	\N	0102000020E6100000020000002C600BC4B4C451C07ABFCDFA0E2F4540737678DDB4C451C0DED6CBFA0E2F4540
1350	249	41	\N	\N	0102000020E610000002000000737678DDB4C451C0DED6CBFA0E2F4540782FF4EBB4C451C08CC0CAFA0E2F4540
1351	249	44	\N	\N	0102000020E610000002000000782FF4EBB4C451C08CC0CAFA0E2F4540EB12E25FB5C451C0C20CC2FA0E2F4540
1352	250	27	\N	\N	0102000020E61000000300000090988F22AFC451C086B4451B192F45400B9E9D22AFC451C01A7627BF1A2F4540ACB59D22AFC451C03C15EBC11A2F4540
1353	250	29	\N	\N	0102000020E610000002000000ACB59D22AFC451C03C15EBC11A2F4540EB6B273BB0C451C05895D2611C2F4540
1354	250	36	\N	\N	0102000020E610000002000000EB6B273BB0C451C05895D2611C2F454029AC283BB0C451C0A09921871C2F4540
1355	250	39	\N	\N	0102000020E61000000200000029AC283BB0C451C0A09921871C2F4540F3AC283BB0C451C0DF1A39871C2F4540
1356	250	41	\N	\N	0102000020E610000002000000F3AC283BB0C451C0DF1A39871C2F454035AD283BB0C451C0B4BB40871C2F4540
1357	250	43	\N	\N	0102000020E61000000200000035AD283BB0C451C0B4BB40871C2F45406175343BB0C451C0DFCEA3E61D2F4540
1358	250	46	\N	\N	0102000020E6100000020000006175343BB0C451C0DFCEA3E61D2F4540DF76343BB0C451C0AE54D0E61D2F4540
1359	250	47	\N	\N	0102000020E610000002000000DF76343BB0C451C0AE54D0E61D2F45400D89373BB0C451C0E58867421E2F4540
1360	250	48	\N	\N	0102000020E6100000020000000D89373BB0C451C0E58867421E2F4540E10A443BB0C451C0B1A06BB71F2F4540
1361	250	51	\N	\N	0102000020E610000002000000E10A443BB0C451C0B1A06BB71F2F454072E24B3BB0C451C030CA4DA1202F4540
1362	250	52	\N	\N	0102000020E61000000200000072E24B3BB0C451C030CA4DA1202F45408BA1693BB0C451C03B637818242F4540
1363	250	53	\N	\N	0102000020E6100000020000008BA1693BB0C451C03B637818242F4540D0A8693BB0C451C054435119242F4540
1364	250	54	\N	\N	0102000020E610000002000000D0A8693BB0C451C054435119242F45402AE1693BB0C451C05FDAE11F242F4540
1365	251	8	\N	\N	0102000020E610000002000000FEDA8C22AFC451C029BA34C9182F454052DD8C22AFC451C02D6A7AC9182F4540
1366	251	10	\N	\N	0102000020E61000000200000052DD8C22AFC451C02D6A7AC9182F4540C4908F22AFC451C0713D5C1A192F4540
1367	251	12	\N	\N	0102000020E610000002000000C4908F22AFC451C0713D5C1A192F45405F928F22AFC451C0C1438C1A192F4540
1368	251	14	\N	\N	0102000020E6100000020000005F928F22AFC451C0C1438C1A192F454054978F22AFC451C04EC4201B192F4540
1369	251	16	\N	\N	0102000020E61000000200000054978F22AFC451C04EC4201B192F454090988F22AFC451C086B4451B192F4540
1370	252	29	\N	\N	0102000020E610000002000000CF08EF58B0C451C097CBBB58152F4540B825E52DB0C451C06BCB9698152F4540
1371	252	32	\N	\N	0102000020E610000002000000B825E52DB0C451C06BCB9698152F4540AEFA3787AFC451C06C1CE28F162F4540
1372	252	34	\N	\N	0102000020E610000002000000AEFA3787AFC451C06C1CE28F162F454085D57E22AFC451C04CF85225172F4540
1373	252	52	\N	\N	0102000020E61000000200000085D57E22AFC451C04CF85225172F454032D38C22AFC451C0E1434BC8182F4540
1374	252	54	\N	\N	0102000020E61000000200000032D38C22AFC451C0E1434BC8182F4540CDD48C22AFC451C0084A7BC8182F4540
1375	252	56	\N	\N	0102000020E610000002000000CDD48C22AFC451C0084A7BC8182F4540C2D98C22AFC451C012CA0FC9182F4540
1376	252	58	\N	\N	0102000020E610000002000000C2D98C22AFC451C012CA0FC9182F4540FEDA8C22AFC451C029BA34C9182F4540
1377	253	6	\N	\N	0102000020E610000002000000ECFCB613AFC451C0A702B08A112F454024CBAC13AFC451C0628E5659102F4540
1378	253	7	\N	\N	0102000020E61000000300000024CBAC13AFC451C0628E5659102F4540BFE10D0DAFC451C0DDCA854F102F4540BFB60A0DAFC451C01BFC9FF00F2F4540
1379	253	11	\N	\N	0102000020E610000002000000BFB60A0DAFC451C01BFC9FF00F2F4540693236F0AEC451C07717E2C50F2F4540
1380	253	12	\N	\N	0102000020E610000002000000693236F0AEC451C07717E2C50F2F45402FFE8CE5ACC451C00ECA04BF0C2F4540
1381	254	6	\N	\N	0102000020E610000002000000401EBA13AFC451C0FFA471E8112F45400A18BA13AFC451C02C9AB7E7112F4540
1382	254	8	\N	\N	0102000020E6100000020000000A18BA13AFC451C02C9AB7E7112F45408616BA13AFC451C004318AE7112F4540
1383	254	10	\N	\N	0102000020E6100000020000008616BA13AFC451C004318AE7112F454053FEB613AFC451C0F1FCD98A112F4540
1384	254	12	\N	\N	0102000020E61000000200000053FEB613AFC451C0F1FCD98A112F4540ECFCB613AFC451C0A702B08A112F4540
1385	255	18	\N	\N	0102000020E610000002000000CE82D713AFC451C04CB9D358152F45403B82D713AFC451C0DE7DC258152F4540
1386	255	20	\N	\N	0102000020E6100000020000003B82D713AFC451C0DE7DC258152F4540987CD713AFC451C068AE1958152F4540
1387	255	23	\N	\N	0102000020E610000002000000987CD713AFC451C068AE1958152F4540FD7BD713AFC451C09B8B0758152F4540
1388	255	26	\N	\N	0102000020E610000002000000FD7BD713AFC451C09B8B0758152F4540147BD713AFC451C03A45EC57152F4540
1389	255	29	\N	\N	0102000020E610000002000000147BD713AFC451C03A45EC57152F4540617AD713AFC451C0454BD757152F4540
1390	255	32	\N	\N	0102000020E610000002000000617AD713AFC451C0454BD757152F45409976D713AFC451C070246657152F4540
1391	255	33	\N	\N	0102000020E6100000030000009976D713AFC451C070246657152F4540F022C813AFC451C0A467538C132F4540B1A8C113AFC451C00CFE4ECA122F4540
1392	255	34	\N	\N	0102000020E610000002000000B1A8C113AFC451C00CFE4ECA122F4540A71FBA13AFC451C03C9F9BE8112F4540
1393	255	36	\N	\N	0102000020E610000002000000A71FBA13AFC451C03C9F9BE8112F4540401EBA13AFC451C0FFA471E8112F4540
1394	256	6	\N	\N	0102000020E6100000020000002FFE8CE5ACC451C00ECA04BF0C2F45408AF68CE5ACC451C01CFB1DBE0C2F4540
1395	256	9	\N	\N	0102000020E6100000020000008AF68CE5ACC451C01CFB1DBE0C2F45409A9752E5ACC451C0506A7DDB052F4540
1396	256	10	\N	\N	0102000020E6100000030000009A9752E5ACC451C0506A7DDB052F454049A31AA6ACC451C0EEF3C37D052F4540AE2509A6ACC451C0CC841B6D032F4540
1397	256	12	\N	\N	0102000020E610000003000000AE2509A6ACC451C0CC841B6D032F45400D7CF4BEACC451C0A8962248032F4540FF5DF1BEACC451C02918F2E9022F4540
1398	257	14	\N	\N	0102000020E6100000020000002FFE8CE5ACC451C00ECA04BF0C2F454076F16E73ACC451C039FE54680D2F4540
1399	257	15	\N	\N	0102000020E61000000200000076F16E73ACC451C039FE54680D2F4540A8EFDF3EACC451C07EDF4FB60D2F4540
1400	257	18	\N	\N	0102000020E610000002000000A8EFDF3EACC451C07EDF4FB60D2F454011FF6A86ABC451C0BC7AFCC70E2F4540
1401	257	21	\N	\N	0102000020E61000000200000011FF6A86ABC451C0BC7AFCC70E2F4540ADA2BA75ABC451C01748BFE00E2F4540
1402	257	23	\N	\N	0102000020E610000002000000ADA2BA75ABC451C01748BFE00E2F454064F48763ABC451C0F141BFFB0E2F4540
1403	257	28	\N	\N	0102000020E61000000200000064F48763ABC451C0F141BFFB0E2F45401E1B1EE5AAC451C0A567C8FB0E2F4540
1404	258	35	\N	\N	0102000020E61000000200000062CC87BFACC451C0AA62721B192F454095CD87BFACC451C0BB99961B192F4540
1405	258	37	\N	\N	0102000020E61000000200000095CD87BFACC451C0BB99961B192F4540D8CF87BFACC451C0DFE6DA1B192F4540
1406	258	39	\N	\N	0102000020E610000002000000D8CF87BFACC451C0DFE6DA1B192F4540A1E791BFACC451C000D6CB4C1A2F4540
1407	258	42	\N	\N	0102000020E610000003000000A1E791BFACC451C000D6CB4C1A2F45405F6B95BBACC451C0FBE5B5521A2F45408FD198BBACC451C0E0A86AB91A2F4540
1408	258	46	\N	\N	0102000020E6100000020000008FD198BBACC451C0E0A86AB91A2F4540E61995BEABC451C0C451CE301C2F4540
1409	258	61	\N	\N	0102000020E610000003000000E61995BEABC451C0C451CE301C2F45409D8FA1BEABC451C0E47BADAA1D2F45403C7DFE7EABC451C0BAF517091E2F4540
1410	258	68	\N	\N	0102000020E6100000020000003C7DFE7EABC451C0BAF517091E2F45401567227FABC451C07DF5424B222F4540
1411	258	69	\N	\N	0102000020E6100000020000001567227FABC451C07DF5424B222F45405470227FABC451C011975B4C222F4540
1412	258	70	\N	\N	0102000020E6100000040000005470227FABC451C011975B4C222F4540E5C02C7FABC451C03B177785232F45401A22C098ABC451C073C261AB232F4540B0BFC398ABC451C02C8A1719242F4540
1413	259	8	\N	\N	0102000020E610000002000000071585BFACC451C04C6861C9182F45403A1685BFACC451C06D9F85C9182F4540
1414	259	10	\N	\N	0102000020E6100000020000003A1685BFACC451C06D9F85C9182F45407D1885BFACC451C0AEECC9C9182F4540
1415	259	12	\N	\N	0102000020E6100000020000007D1885BFACC451C0AEECC9C9182F454000C687BFACC451C00795B11A192F4540
1416	259	14	\N	\N	0102000020E61000000200000000C687BFACC451C00795B11A192F454090C787BFACC451C00FB7E01A192F4540
1417	259	16	\N	\N	0102000020E61000000200000090C787BFACC451C00FB7E01A192F454062CC87BFACC451C0AA62721B192F4540
1418	260	26	\N	\N	0102000020E6100000020000008385E7F5ADC451C068ADE858152F4540E34737E5ADC451C04849AB71152F4540
1419	260	28	\N	\N	0102000020E610000002000000E34737E5ADC451C04849AB71152F45401E9996D1ADC451C0EA45CA8E152F4540
1420	260	30	\N	\N	0102000020E6100000020000001E9996D1ADC451C0EA45CA8E152F45402BC27781ADC451C0C5A7A905162F4540
1421	260	31	\N	\N	0102000020E6100000020000002BC27781ADC451C0C5A7A905162F4540B38A60D7ACC451C0A58E0502172F4540
1422	260	32	\N	\N	0102000020E610000002000000B38A60D7ACC451C0A58E0502172F4540582F77BFACC451C06BA67F25172F4540
1423	260	48	\N	\N	0102000020E610000002000000582F77BFACC451C06BA67F25172F4540A50E85BFACC451C0159BA0C8182F4540
1424	260	50	\N	\N	0102000020E610000002000000A50E85BFACC451C0159BA0C8182F4540351085BFACC451C003BDCFC8182F4540
1425	260	52	\N	\N	0102000020E610000002000000351085BFACC451C003BDCFC8182F4540071585BFACC451C04C6861C9182F4540
1426	261	10	\N	\N	0102000020E610000002000000E6134F4DA3C451C05887888B112F454095124F4DA3C451C04F475F8B112F4540
1427	261	12	\N	\N	0102000020E61000000200000095124F4DA3C451C04F475F8B112F4540F60C4F4DA3C451C0463FAF8A112F4540
1428	261	14	\N	\N	0102000020E610000003000000F60C4F4DA3C451C0463FAF8A112F45400BAC414DA3C451C059C4A6E70F2F4540D7673F4DA3C451C09409AAA00F2F4540
1429	261	20	\N	\N	0102000020E610000002000000D7673F4DA3C451C09409AAA00F2F45405F5A2C3DA5C451C0D722E1C00C2F4540
1430	262	8	\N	\N	0102000020E6100000020000003512524DA3C451C0B5294AE9112F4540E410524DA3C451C09FE920E9112F4540
1431	262	10	\N	\N	0102000020E610000002000000E410524DA3C451C09FE920E9112F4540450B524DA3C451C05DE170E8112F4540
1432	262	12	\N	\N	0102000020E610000002000000450B524DA3C451C05DE170E8112F45407C1A4F4DA3C451C0E3DA568C112F4540
1433	262	14	\N	\N	0102000020E6100000020000007C1A4F4DA3C451C0E3DA568C112F454047194F4DA3C451C074FA308C112F4540
1434	262	16	\N	\N	0102000020E61000000200000047194F4DA3C451C074FA308C112F4540E6134F4DA3C451C05887888B112F4540
1435	263	22	\N	\N	0102000020E610000002000000F12D6E4DA3C451C0223EAC59152F45406A2D6E4DA3C451C032C69B59152F4540
1436	263	24	\N	\N	0102000020E6100000020000006A2D6E4DA3C451C032C69B59152F4540A02C6E4DA3C451C0F9FD8259152F4540
1437	263	27	\N	\N	0102000020E610000002000000A02C6E4DA3C451C0F9FD8259152F4540042C6E4DA3C451C0BDEB6F59152F4540
1438	263	30	\N	\N	0102000020E610000002000000042C6E4DA3C451C0BDEB6F59152F4540BA286E4DA3C451C0B3DF0859152F4540
1439	263	33	\N	\N	0102000020E610000002000000BA286E4DA3C451C0B3DF0859152F454001276E4DA3C451C06FF5D258152F4540
1440	263	36	\N	\N	0102000020E61000000200000001276E4DA3C451C06FF5D258152F454058266E4DA3C451C0FE38BE58152F4540
1441	263	39	\N	\N	0102000020E61000000200000058266E4DA3C451C0FE38BE58152F454097256E4DA3C451C031A6A658152F4540
1442	263	40	\N	\N	0102000020E61000000300000097256E4DA3C451C031A6A658152F4540127A5F4DA3C451C068EC2B8D132F4540CB18524DA3C451C0417D18EA112F4540
1443	263	42	\N	\N	0102000020E610000002000000CB18524DA3C451C0417D18EA112F45409617524DA3C451C0D09CF2E9112F4540
1444	263	44	\N	\N	0102000020E6100000020000009617524DA3C451C0D09CF2E9112F45403512524DA3C451C0B5294AE9112F4540
1445	264	13	\N	\N	0102000020E6100000020000005F5A2C3DA5C451C0D722E1C00C2F454079532C3DA5C451C023B50AC00C2F4540
1446	264	16	\N	\N	0102000020E61000000200000079532C3DA5C451C023B50AC00C2F45402A532C3DA5C451C0F80601C00C2F4540
1447	264	19	\N	\N	0102000020E6100000020000002A532C3DA5C451C0F80601C00C2F45402F4C2C3DA5C451C0082228BF0C2F4540
1448	264	22	\N	\N	0102000020E6100000020000002F4C2C3DA5C451C0082228BF0C2F454025A0F33CA5C451C0EEC259DD052F4540
1449	264	23	\N	\N	0102000020E61000000300000025A0F33CA5C451C0EEC259DD052F454025B3077DA5C451C0088F477E052F45409CADF67CA5C451C0D91F9F6D032F4540
1450	264	25	\N	\N	0102000020E6100000030000009CADF67CA5C451C0D91F9F6D032F454087D1F662A5C451C088631347032F45402AD3F362A5C451C01C6310EA022F4540
1451	264	26	\N	\N	0102000020E6100000020000002AD3F362A5C451C01C6310EA022F454076C9F362A5C451C008E5E2E8022F4540
1452	265	10	\N	\N	0102000020E6100000020000005F5A2C3DA5C451C0D722E1C00C2F4540D5594953A5C451C03AE0A9E10C2F4540
1453	265	13	\N	\N	0102000020E610000002000000D5594953A5C451C03AE0A9E10C2F45405A98B0FFA5C451C0A6CB42E10D2F4540
1454	265	14	\N	\N	0102000020E6100000020000005A98B0FFA5C451C0A6CB42E10D2F45402A13AA0BA6C451C08D8903F30D2F4540
1455	265	17	\N	\N	0102000020E6100000020000002A13AA0BA6C451C08D8903F30D2F4540EC7274BEA6C451C067A014FC0E2F4540
1456	265	20	\N	\N	0102000020E610000002000000EC7274BEA6C451C067A014FC0E2F4540FDDCA23EA7C451C00B7F0BFC0E2F4540
1457	266	29	\N	\N	0102000020E6100000030000006EEC5366A3C451C05C8E1D1C192F45409D556166A3C451C0FF4FFFBF1A2F454083C66466A3C451C0805FBB2B1B2F4540
1458	266	32	\N	\N	0102000020E61000000200000083C66466A3C451C0805FBB2B1B2F4540D6DCD43DA5C451C08839A9E61D2F4540
1459	266	51	\N	\N	0102000020E610000003000000D6DCD43DA5C451C08839A9E61D2F45409C04E13DA5C451C0766388601F2F4540A8408A7DA5C451C0ADBEE9BE1F2F4540
1460	266	55	\N	\N	0102000020E610000002000000A8408A7DA5C451C0ADBEE9BE1F2F45400D4E9B7DA5C451C0969881D0212F4540
1461	266	58	\N	\N	0102000020E6100000030000000D4E9B7DA5C451C0969881D0212F45409D444364A5C451C0DB8E1BF6212F4540ED114664A5C451C02288294D222F4540
1462	267	11	\N	\N	0102000020E610000002000000694D5166A3C451C0FB930CCA182F4540B5515166A3C451C0DD2893CA182F4540
1463	267	13	\N	\N	0102000020E610000002000000B5515166A3C451C0DD2893CA182F4540C6525166A3C451C0378BB4CA182F4540
1464	267	15	\N	\N	0102000020E610000002000000C6525166A3C451C0378BB4CA182F4540C8545166A3C451C04F6BF3CA182F4540
1465	267	17	\N	\N	0102000020E610000002000000C8545166A3C451C04F6BF3CA182F454029E45366A3C451C0F9AD1A1B192F4540
1466	267	18	\N	\N	0102000020E61000000200000029E45366A3C451C0F9AD1A1B192F45408FE65366A3C451C066CB651B192F4540
1467	267	20	\N	\N	0102000020E6100000020000008FE65366A3C451C066CB651B192F454009EB5366A3C451C039EAF11B192F4540
1468	267	22	\N	\N	0102000020E61000000200000009EB5366A3C451C039EAF11B192F45406EEC5366A3C451C05C8E1D1C192F4540
1469	268	19	\N	\N	0102000020E610000002000000DF9AB52FA2C451C07843C059152F4540015016E8A2C451C059EF196B162F4540
1470	268	21	\N	\N	0102000020E610000002000000015016E8A2C451C059EF196B162F45403CE44366A3C451C00ED22A26172F4540
1471	268	38	\N	\N	0102000020E6100000020000003CE44366A3C451C00ED22A26172F4540694D5166A3C451C0FB930CCA182F4540
1472	269	6	\N	\N	0102000020E61000000300000097507184A0C451C06D51BA8B112F4540D40D6484A0C451C06C8ED8E70F2F4540E4CF6184A0C451C0A3D3DBA00F2F4540
1473	269	12	\N	\N	0102000020E610000002000000E4CF6184A0C451C0A3D3DBA00F2F4540BC6860939EC451C04A9D03C00C2F4540
1474	270	8	\N	\N	0102000020E6100000020000009F467484A0C451C0CBF37BE9112F454031417484A0C451C0E0FACFE8112F4540
1475	270	10	\N	\N	0102000020E61000000200000031417484A0C451C0E0FACFE8112F4540D23F7484A0C451C011A9A4E8112F4540
1476	270	12	\N	\N	0102000020E610000002000000D23F7484A0C451C011A9A4E8112F45400D577184A0C451C05DE0868C112F4540
1477	270	14	\N	\N	0102000020E6100000020000000D577184A0C451C05DE0868C112F4540DD517184A0C451C0C595E28B112F4540
1478	270	16	\N	\N	0102000020E610000002000000DD517184A0C451C0C595E28B112F454097507184A0C451C06D51BA8B112F4540
1479	271	22	\N	\N	0102000020E61000000200000097149084A0C451C03E08DE59152F454000149084A0C451C05969CB59152F4540
1480	271	24	\N	\N	0102000020E61000000200000000149084A0C451C05969CB59152F4540D3109084A0C451C012C16659152F4540
1481	271	27	\N	\N	0102000020E610000002000000D3109084A0C451C012C16659152F4540290F9084A0C451C0900F3259152F4540
1482	271	30	\N	\N	0102000020E610000002000000290F9084A0C451C0900F3259152F4540850E9084A0C451C023CA1D59152F4540
1483	271	33	\N	\N	0102000020E610000002000000850E9084A0C451C023CA1D59152F4540CA0D9084A0C451C0CEBD0659152F4540
1484	271	36	\N	\N	0102000020E610000002000000CA0D9084A0C451C0CEBD0659152F4540590D9084A0C451C00FB6F858152F4540
1485	271	39	\N	\N	0102000020E610000002000000590D9084A0C451C00FB6F858152F4540E0079084A0C451C0267E4B58152F4540
1486	271	40	\N	\N	0102000020E610000003000000E0079084A0C451C0267E4B58152F454065898184A0C451C081B65D8D132F4540154D7484A0C451C0028248EA112F4540
1487	271	42	\N	\N	0102000020E610000002000000154D7484A0C451C0028248EA112F4540E5477484A0C451C00038A4E9112F4540
1488	271	44	\N	\N	0102000020E610000002000000E5477484A0C451C00038A4E9112F45409F467484A0C451C0CBF37BE9112F4540
1489	272	6	\N	\N	0102000020E610000002000000BC6860939EC451C04A9D03C00C2F4540756460939EC451C09B2D7BBF0C2F4540
1490	272	9	\N	\N	0102000020E610000002000000756460939EC451C09B2D7BBF0C2F4540BA2629939EC451C08496EBDC052F4540
1491	272	10	\N	\N	0102000020E610000003000000BA2629939EC451C08496EBDC052F4540A83380539EC451C0B81B8A7E052F45405DB16F539EC451C0C083456F032F4540
1492	272	12	\N	\N	0102000020E6100000030000005DB16F539EC451C0C083456F032F4540BEA0CF6C9EC451C0CFC99F49032F4540ACA9CC6C9EC451C0BFD2F5EA022F4540
1493	273	9	\N	\N	0102000020E610000002000000BC6860939EC451C04A9D03C00C2F4540FBCBE9D09DC451C05A6587E00D2F4540
1494	273	10	\N	\N	0102000020E610000002000000FBCBE9D09DC451C05A6587E00D2F4540F18E48C59DC451C07390C8F10D2F4540
1495	273	13	\N	\N	0102000020E610000002000000F18E48C59DC451C07390C8F10D2F4540826931119DC451C0EC51F9FC0E2F4540
1496	273	18	\N	\N	0102000020E610000002000000826931119DC451C0EC51F9FC0E2F45407862CE929CC451C0DAF801FD0E2F4540
1497	274	36	\N	\N	0102000020E6100000020000003F3DB974A0C451C0C231521C192F4540973EB974A0C451C06FBC7C1C192F4540
1498	274	38	\N	\N	0102000020E610000002000000973EB974A0C451C06FBC7C1C192F4540BA42B974A0C451C07BD3FF1C192F4540
1499	274	40	\N	\N	0102000020E610000002000000BA42B974A0C451C07BD3FF1C192F4540C143B974A0C451C09E51201D192F4540
1500	274	42	\N	\N	0102000020E610000003000000C143B974A0C451C09E51201D192F45403A7FC674A0C451C069F333C01A2F4540567CC974A0C451C0CD7FDB1E1B2F4540
1501	274	45	\N	\N	0102000020E610000002000000567CC974A0C451C0CD7FDB1E1B2F4540345E05949EC451C0680B24E81D2F4540
1502	274	62	\N	\N	0102000020E610000003000000345E05949EC451C0680B24E81D2F4540EB3911949EC451C0E9AD7C621F2F4540200C0D569EC451C0F4207FBE1F2F4540
1503	274	69	\N	\N	0102000020E610000002000000200C0D569EC451C0F4207FBE1F2F4540A1B71D569EC451C04BFEDED2212F4540
1504	274	72	\N	\N	0102000020E610000003000000A1B71D569EC451C04BFEDED2212F45403B3B156E9EC451C0543D67F6212F454083F1176E9EC451C012BEFB4C222F4540
1505	275	12	\N	\N	0102000020E610000002000000E5A5B674A0C451C0603741CA182F45403DA7B674A0C451C0DBC16BCA182F4540
1506	275	14	\N	\N	0102000020E6100000020000003DA7B674A0C451C0DBC16BCA182F454060ABB674A0C451C04BD8EECA182F4540
1507	275	16	\N	\N	0102000020E61000000200000060ABB674A0C451C04BD8EECA182F454067ACB674A0C451C046560FCB182F4540
1508	275	18	\N	\N	0102000020E61000000200000067ACB674A0C451C046560FCB182F45407035B974A0C451C080EA5A1B192F4540
1509	275	20	\N	\N	0102000020E6100000020000007035B974A0C451C080EA5A1B192F45409D36B974A0C451C0782D801B192F4540
1510	275	22	\N	\N	0102000020E6100000020000009D36B974A0C451C0782D801B192F4540EE38B974A0C451C02882C91B192F4540
1511	275	24	\N	\N	0102000020E610000002000000EE38B974A0C451C02882C91B192F45403F3DB974A0C451C0C231521C192F4540
1512	276	23	\N	\N	0102000020E6100000020000008B451B3E9FC451C011A7F459152F4540B7CF1C3E9FC451C074EFF659152F4540
1513	276	25	\N	\N	0102000020E610000002000000B7CF1C3E9FC451C074EFF659152F4540924AC510A0C451C0AE3D4792162F4540
1514	276	27	\N	\N	0102000020E610000002000000924AC510A0C451C0AE3D4792162F4540EC63A974A0C451C070755F26172F4540
1515	276	46	\N	\N	0102000020E610000002000000EC63A974A0C451C070755F26172F4540E5A5B674A0C451C0603741CA182F4540
1516	277	27	\N	\N	0102000020E6100000030000009D9D414497C451C0379FF21C192F454034654E4497C451C0E960D4C01A2F4540984B504497C451C042D340FF1A2F4540
1517	277	28	\N	\N	0102000020E610000002000000984B504497C451C042D340FF1A2F4540121FE81298C451C043038B311C2F4540
1518	277	43	\N	\N	0102000020E610000003000000121FE81298C451C043038B311C2F4540B9ACF31298C451C007A6E3AB1D2F454065F33B5498C451C08FCFAC0C1E2F4540
1519	277	50	\N	\N	0102000020E61000000400000065F33B5498C451C08FCFAC0C1E2F45408EC5665498C451C0559A8285232F45405904733998C451C007357FAD232F45409182753998C451C0E79016FF232F4540
1520	277	51	\N	\N	0102000020E6100000020000009182753998C451C0E79016FF232F454097A9753998C451C0B9B51304242F4540
1521	277	52	\N	\N	0102000020E61000000200000097A9753998C451C0B9B51304242F45406DC27B3F99C451C0C2718B88252F4540
1522	277	54	\N	\N	0102000020E6100000020000006DC27B3F99C451C0C2718B88252F4540BEFD7B3F99C451C096B61890252F4540
1523	278	9	\N	\N	0102000020E6100000020000002E1E3F4497C451C0D4A4E1CA182F454004223F4497C451C0F29D5FCB182F4540
1524	278	11	\N	\N	0102000020E61000000200000004223F4497C451C0F29D5FCB182F454034233F4497C451C0E3B986CB182F4540
1525	278	13	\N	\N	0102000020E61000000200000034233F4497C451C0E3B986CB182F45401495414497C451C0893EDA1B192F4540
1526	278	14	\N	\N	0102000020E6100000020000001495414497C451C0893EDA1B192F4540809A414497C451C08D608C1C192F4540
1527	278	16	\N	\N	0102000020E610000002000000809A414497C451C08D608C1C192F45408D9B414497C451C031DBAE1C192F4540
1528	278	18	\N	\N	0102000020E6100000020000008D9B414497C451C031DBAE1C192F45409D9D414497C451C0379FF21C192F4540
1529	279	22	\N	\N	0102000020E610000002000000A9E6A37A98C451C00CBB6A5A152F45400F6D8D7C97C451C09F7663D3162F4540
1530	279	23	\N	\N	0102000020E6100000020000000F6D8D7C97C451C09F7663D3162F45409956324497C451C0D5E2FF26172F4540
1531	279	40	\N	\N	0102000020E6100000020000009956324497C451C0D5E2FF26172F4540111B3F4497C451C022667BCA182F4540
1532	279	42	\N	\N	0102000020E610000002000000111B3F4497C451C022667BCA182F45401E1C3F4497C451C0C7E09DCA182F4540
1533	279	44	\N	\N	0102000020E6100000020000001E1C3F4497C451C0C7E09DCA182F45402E1E3F4497C451C0D4A4E1CA182F4540
1534	280	10	\N	\N	0102000020E61000000200000028C7520595C451C05A26828C112F4540F9C5520595C451C03FEB5A8C112F4540
1535	280	12	\N	\N	0102000020E610000002000000F9C5520595C451C03FEB5A8C112F4540D8C0520595C451C01AC8B08B112F4540
1536	280	14	\N	\N	0102000020E610000003000000D8C0520595C451C01AC8B08B112F4540821D460595C451C04B63A0E80F2F4540DA84430595C451C0B71E89920F2F4540
1537	280	20	\N	\N	0102000020E610000002000000DA84430595C451C0B71E89920F2F454028C4FFEA96C451C04F6DE2C10C2F4540
1538	281	8	\N	\N	0102000020E610000002000000FE9A550595C451C0BCC843EA112F4540CF99550595C451C09B8D1CEA112F4540
1539	281	10	\N	\N	0102000020E610000002000000CF99550595C451C09B8D1CEA112F4540AE94550595C451C0566A72E9112F4540
1540	281	12	\N	\N	0102000020E610000002000000AE94550595C451C0566A72E9112F4540EECC520595C451C0E48D418D112F4540
1541	281	14	\N	\N	0102000020E610000002000000EECC520595C451C0E48D418D112F4540D6CB520595C451C08D591D8D112F4540
1542	281	16	\N	\N	0102000020E610000002000000D6CB520595C451C08D591D8D112F454028C7520595C451C05A26828C112F4540
1543	282	16	\N	\N	0102000020E610000002000000EA27700595C451C04EDDA55A152F45405C27700595C451C03E83935A152F4540
1544	282	18	\N	\N	0102000020E6100000020000005C27700595C451C03E83935A152F4540BB26700595C451C010A27E5A152F4540
1545	282	21	\N	\N	0102000020E610000002000000BB26700595C451C010A27E5A152F45405926700595C451C073EA715A152F4540
1546	282	24	\N	\N	0102000020E6100000020000005926700595C451C073EA715A152F45409A21700595C451C0597ED459152F4540
1547	282	27	\N	\N	0102000020E6100000020000009A21700595C451C0597ED459152F45407C20700595C451C0EF7EAF59152F4540
1548	282	28	\N	\N	0102000020E6100000030000007C20700595C451C0EF7EAF59152F4540A644620595C451C0808B258E132F4540C4A0550595C451C06A3003EB112F4540
1549	282	30	\N	\N	0102000020E610000002000000C4A0550595C451C06A3003EB112F4540AC9F550595C451C00CFCDEEA112F4540
1550	282	32	\N	\N	0102000020E610000002000000AC9F550595C451C00CFCDEEA112F4540FE9A550595C451C0BCC843EA112F4540
1551	283	13	\N	\N	0102000020E61000000200000028C4FFEA96C451C04F6DE2C10C2F4540D9BCFFEA96C451C030F0F1C00C2F4540
1552	283	16	\N	\N	0102000020E610000002000000D9BCFFEA96C451C030F0F1C00C2F454020B9FFEA96C451C04D6A77C00C2F4540
1553	283	19	\N	\N	0102000020E61000000200000020B9FFEA96C451C04D6A77C00C2F4540E6A9FFEA96C451C0227182BE0C2F4540
1554	283	22	\N	\N	0102000020E610000002000000E6A9FFEA96C451C0227182BE0C2F4540662ECAEA96C451C06366CADE052F4540
1555	283	23	\N	\N	0102000020E610000003000000662ECAEA96C451C06366CADE052F4540A34D6D2A97C451C020476080052F45400F2E5D2A97C451C0223F686E032F4540
1556	283	25	\N	\N	0102000020E6100000030000000F2E5D2A97C451C0223F686E032F45405CF6D11097C451C0B53D8948032F4540161FCF1097C451C0EB431EEB022F4540
1557	283	26	\N	\N	0102000020E610000002000000161FCF1097C451C0EB431EEB022F45406315CF1097C451C0A446DFE9022F4540
1558	284	17	\N	\N	0102000020E61000000200000028C4FFEA96C451C04F6DE2C10C2F454034EA67ED96C451C07EEB73C50C2F4540
1559	284	19	\N	\N	0102000020E61000000200000034EA67ED96C451C07EEB73C50C2F45405156FAF096C451C004A1BFCA0C2F4540
1560	284	21	\N	\N	0102000020E6100000020000005156FAF096C451C004A1BFCA0C2F45403A4C9D0497C451C0E486DCE70C2F4540
1561	284	23	\N	\N	0102000020E6100000020000003A4C9D0497C451C0E486DCE70C2F45407015D15697C451C023BCBB610D2F4540
1562	284	24	\N	\N	0102000020E6100000020000007015D15697C451C023BCBB610D2F454069D50FC097C451C000A9C4FD0D2F4540
1563	284	27	\N	\N	0102000020E61000000200000069D50FC097C451C000A9C4FD0D2F4540ACFB686C98C451C03E074AFD0E2F4540
1564	284	31	\N	\N	0102000020E610000002000000ACFB686C98C451C03E074AFD0E2F4540D47A887A98C451C0D21349FD0E2F4540
1565	284	34	\N	\N	0102000020E610000002000000D47A887A98C451C0D21349FD0E2F45400B389EEC98C451C07B6541FD0E2F4540
1566	285	27	\N	\N	0102000020E610000003000000BA04327E92C451C0C4A2431D192F4540BD8C3E7E92C451C07C6425C11A2F4540179C3E7E92C451C084C527C31A2F4540
1567	285	28	\N	\N	0102000020E610000002000000179C3E7E92C451C084C527C31A2F45405D01089793C451C0FE1072631C2F4540
1568	285	49	\N	\N	0102000020E6100000020000005D01089793C451C0FE1072631C2F4540316A429793C451C04745AAFF232F4540
1569	285	50	\N	\N	0102000020E610000003000000316A429793C451C04745AAFF232F4540D9A8429793C451C0E123D407242F45402772D49F94C451C0AAB61290252F4540
1570	285	53	\N	\N	0102000020E6100000020000002772D49F94C451C0AAB61290252F4540A076D49F94C451C00341A790252F4540
1571	285	54	\N	\N	0102000020E610000002000000A076D49F94C451C00341A790252F4540418FD49F94C451C01659D993252F4540
1572	286	9	\N	\N	0102000020E610000002000000B8912F7E92C451C05DA832CB182F4540A8932F7E92C451C0438873CB182F4540
1573	286	11	\N	\N	0102000020E610000002000000A8932F7E92C451C0438873CB182F454040972F7E92C451C09EF0EBCB182F4540
1574	286	13	\N	\N	0102000020E61000000200000040972F7E92C451C09EF0EBCB182F45405D982F7E92C451C0244411CC182F4540
1575	286	14	\N	\N	0102000020E6100000020000005D982F7E92C451C0244411CC182F4540A4FE317E92C451C041B0771C192F4540
1576	286	16	\N	\N	0102000020E610000002000000A4FE317E92C451C041B0771C192F4540BE03327E92C451C0329A221D192F4540
1577	286	18	\N	\N	0102000020E610000002000000BE03327E92C451C0329A221D192F4540BA04327E92C451C0C4A2431D192F4540
1578	287	29	\N	\N	0102000020E61000000200000087DF94B493C451C0F225BC5A152F4540A3170DA893C451C06344536D152F4540
1579	287	31	\N	\N	0102000020E610000002000000A3170DA893C451C06344536D152F4540CF81A09193C451C02F19988E152F4540
1580	287	33	\N	\N	0102000020E610000002000000CF81A09193C451C02F19988E152F454064029A8993C451C0C62F809A152F4540
1581	287	36	\N	\N	0102000020E61000000200000064029A8993C451C0C62F809A152F4540F2C10FBF92C451C01C1DFEC6162F4540
1582	287	38	\N	\N	0102000020E610000002000000F2C10FBF92C451C01C1DFEC6162F4540B709237E92C451C05CE65027172F4540
1583	287	54	\N	\N	0102000020E610000002000000B709237E92C451C05CE65027172F4540A28B2F7E92C451C0EBB566CA182F4540
1584	287	56	\N	\N	0102000020E610000002000000A28B2F7E92C451C0EBB566CA182F4540BC902F7E92C451C0CF9F11CB182F4540
1585	287	58	\N	\N	0102000020E610000002000000BC902F7E92C451C0CF9F11CB182F4540B8912F7E92C451C05DA832CB182F4540
1586	288	6	\N	\N	0102000020E6100000030000002C30E13792C451C00177B18C112F4540D8ABD43792C451C0F0B3CFE80F2F45408FCDD23792C451C0859123AA0F2F4540
1587	288	12	\N	\N	0102000020E6100000020000008FCDD23792C451C0859123AA0F2F45406D8E6B4190C451C059C346C10C2F4540
1588	289	8	\N	\N	0102000020E610000002000000ACFBE33792C451C0641973EA112F4540B9F6E33792C451C00222CDE9112F4540
1589	289	10	\N	\N	0102000020E610000002000000B9F6E33792C451C00222CDE9112F4540A6F5E33792C451C04203A9E9112F4540
1590	289	12	\N	\N	0102000020E610000002000000A6F5E33792C451C04203A9E9112F4540D135E13792C451C07BCF6E8D112F4540
1591	289	14	\N	\N	0102000020E610000002000000D135E13792C451C07BCF6E8D112F45405031E13792C451C0FBB2D78C112F4540
1592	289	16	\N	\N	0102000020E6100000020000005031E13792C451C0FBB2D78C112F45402C30E13792C451C00177B18C112F4540
1593	290	16	\N	\N	0102000020E610000002000000563AFE3792C451C0FC2DD55A152F4540F739FE3792C451C051C8C85A152F4540
1594	290	18	\N	\N	0102000020E610000002000000F739FE3792C451C051C8C85A152F45406335FE3792C451C001362F5A152F4540
1595	290	21	\N	\N	0102000020E6100000020000006335FE3792C451C001362F5A152F45405034FE3792C451C01B170B5A152F4540
1596	290	24	\N	\N	0102000020E6100000020000005034FE3792C451C01B170B5A152F4540D933FE3792C451C03B96FB59152F4540
1597	290	27	\N	\N	0102000020E610000002000000D933FE3792C451C03B96FB59152F4540CA32FE3792C451C0700DD859152F4540
1598	290	28	\N	\N	0102000020E610000003000000CA32FE3792C451C0700DD859152F45400280F03792C451C02DDC548E132F45405101E43792C451C06A7230EB112F4540
1599	290	30	\N	\N	0102000020E6100000020000005101E43792C451C06A7230EB112F4540D0FCE33792C451C07A5599EA112F4540
1600	290	32	\N	\N	0102000020E610000002000000D0FCE33792C451C07A5599EA112F4540ACFBE33792C451C0641973EA112F4540
1601	291	6	\N	\N	0102000020E6100000020000006D8E6B4190C451C059C346C10C2F4540CE7F6B4190C451C0954458BF0C2F4540
1602	291	9	\N	\N	0102000020E610000002000000CE7F6B4190C451C0954458BF0C2F4540D970374190C451C0B734A8DE052F4540
1603	291	10	\N	\N	0102000020E610000003000000D970374190C451C0B734A8DE052F4540A3A88E0190C451C0527A4680052F454040117F0190C451C071B56670032F4540
1604	291	12	\N	\N	0102000020E61000000300000040117F0190C451C071B56670032F454003CEA21A90C451C0CD7D1A4B032F45405AFE9F1A90C451C02F0EF7EB022F4540
1605	292	14	\N	\N	0102000020E6100000020000006D8E6B4190C451C059C346C10C2F45409B58EC1E90C451C084E274F40C2F4540
1606	292	15	\N	\N	0102000020E6100000020000009B58EC1E90C451C084E274F40C2F4540B768E1768FC451C00C74C4ED0D2F4540
1607	292	18	\N	\N	0102000020E610000002000000B768E1768FC451C00C74C4ED0D2F454040BB38E28EC451C09AEF51CA0E2F4540
1608	292	21	\N	\N	0102000020E61000000200000040BB38E28EC451C09AEF51CA0E2F4540EFE287D18EC451C0163215E30E2F4540
1609	292	23	\N	\N	0102000020E610000002000000EFE287D18EC451C0163215E30E2F454050E746BF8EC451C0321B2AFE0E2F4540
1610	292	28	\N	\N	0102000020E61000000200000050E746BF8EC451C0321B2AFE0E2F4540543F7B408EC451C09B4A32FE0E2F4540
1611	293	31	\N	\N	0102000020E61000000200000040382A1B90C451C0EA8B6B1D192F454034392A1B90C451C075DB8B1D192F4540
1612	293	33	\N	\N	0102000020E61000000200000034392A1B90C451C075DB8B1D192F4540143B2A1B90C451C04949CB1D192F4540
1613	293	35	\N	\N	0102000020E610000002000000143B2A1B90C451C04949CB1D192F45408E3E2A1B90C451C049E9401E192F4540
1614	293	37	\N	\N	0102000020E6100000040000008E3E2A1B90C451C049E9401E192F4540153E331B90C451C05AFFC44E1A2F454088DF771790C451C016644E541A2F45401EEE7A1790C451C01A65C4BB1A2F4540
1615	293	38	\N	\N	0102000020E6100000020000001EEE7A1790C451C01A65C4BB1A2F4540D078721A8FC451C0F5222B331C2F4540
1616	293	53	\N	\N	0102000020E610000003000000D078721A8FC451C0F5222B331C2F4540169E7D1A8FC451C0091FF3AD1D2F4540E835DADA8EC451C0B6195D0C1E2F4540
1617	293	60	\N	\N	0102000020E610000002000000E835DADA8EC451C0B6195D0C1E2F454049D4EEDA8EC451C00AE9D0C9202F4540
1618	293	61	\N	\N	0102000020E61000000200000049D4EEDA8EC451C00AE9D0C9202F4540187803DB8EC451C02A88FD87232F4540
1619	293	62	\N	\N	0102000020E610000003000000187803DB8EC451C02A88FD87232F4540909395F48EC451C09CB6E6AD232F454047FF97F48EC451C082943800242F4540
1620	294	10	\N	\N	0102000020E61000000200000074CB271B90C451C084915ACB182F454068CC271B90C451C01BE17ACB182F4540
1621	294	12	\N	\N	0102000020E61000000200000068CC271B90C451C01BE17ACB182F454048CE271B90C451C00D4FBACB182F4540
1622	294	14	\N	\N	0102000020E61000000200000048CE271B90C451C00D4FBACB182F4540C2D1271B90C451C040EF2FCC182F4540
1623	294	16	\N	\N	0102000020E610000002000000C2D1271B90C451C040EF2FCC182F454048322A1B90C451C0418CA11C192F4540
1624	294	18	\N	\N	0102000020E61000000200000048322A1B90C451C0418CA11C192F45404E332A1B90C451C0B93DC41C192F4540
1625	294	20	\N	\N	0102000020E6100000020000004E332A1B90C451C0B93DC41C192F454040382A1B90C451C0EA8B6B1D192F4540
1626	295	26	\N	\N	0102000020E610000002000000EE5B8D5191C451C0C842E45A152F454062A2DC4091C451C0C853A773152F4540
1627	295	28	\N	\N	0102000020E61000000200000062A2DC4091C451C0C853A773152F4540DED23B2D91C451C08532C690152F4540
1628	295	30	\N	\N	0102000020E610000002000000DED23B2D91C451C08532C690152F45401F57CFDC90C451C07D851708162F4540
1629	295	31	\N	\N	0102000020E6100000020000001F57CFDC90C451C07D851708162F4540A0B8973090C451C0E6729807172F4540
1630	295	32	\N	\N	0102000020E610000002000000A0B8973090C451C0E6729807172F45403D631B1B90C451C07DCF7827172F4540
1631	295	48	\N	\N	0102000020E6100000020000003D631B1B90C451C07DCF7827172F45407CC5271B90C451C0549290CA182F4540
1632	295	50	\N	\N	0102000020E6100000020000007CC5271B90C451C0549290CA182F454082C6271B90C451C0B643B3CA182F4540
1633	295	52	\N	\N	0102000020E61000000200000082C6271B90C451C0B643B3CA182F454074CB271B90C451C084915ACB182F4540
1634	296	11	\N	\N	0102000020E61000000200000049F82F7D86C451C0948B718D112F45405DF72F7D86C451C06D18518D112F4540
1635	296	13	\N	\N	0102000020E6100000020000005DF72F7D86C451C06D18518D112F4540BAF22F7D86C451C07891AD8C112F4540
1636	296	15	\N	\N	0102000020E610000003000000BAF22F7D86C451C07891AD8C112F45402D10247D86C451C073C88FE90F2F45406DC3237D86C451C0CC34FDDE0F2F4540
1637	296	21	\N	\N	0102000020E6100000020000006DC3237D86C451C0CC34FDDE0F2F45400CF4A88B86C451C0A86372C90F2F4540
1638	296	22	\N	\N	0102000020E6100000020000000CF4A88B86C451C0A86372C90F2F454099BC849788C451C0804C40C00C2F4540
1639	297	8	\N	\N	0102000020E610000002000000E8A0327D86C451C0F82D33EB112F4540FC9F327D86C451C0C7BA12EB112F4540
1640	297	10	\N	\N	0102000020E610000002000000FC9F327D86C451C0C7BA12EB112F4540599B327D86C451C093336FEA112F4540
1641	297	12	\N	\N	0102000020E610000002000000599B327D86C451C093336FEA112F454076FD2F7D86C451C01F1F288E112F4540
1642	297	14	\N	\N	0102000020E61000000200000076FD2F7D86C451C01F1F288E112F45407FFC2F7D86C451C0BF0E068E112F4540
1643	297	16	\N	\N	0102000020E6100000020000007FFC2F7D86C451C0BF0E068E112F454049F82F7D86C451C0948B718D112F4540
1644	298	22	\N	\N	0102000020E61000000200000007984B7D86C451C0B042955B152F45401B974B7D86C451C068CF745B152F4540
1645	298	24	\N	\N	0102000020E6100000020000001B974B7D86C451C068CF745B152F4540B6964B7D86C451C07ADE665B152F4540
1646	298	27	\N	\N	0102000020E610000002000000B6964B7D86C451C07ADE665B152F4540CE954B7D86C451C0FDE2465B152F4540
1647	298	30	\N	\N	0102000020E610000002000000CE954B7D86C451C0FDE2465B152F4540E5934B7D86C451C0BE84035B152F4540
1648	298	33	\N	\N	0102000020E610000002000000E5934B7D86C451C0BE84035B152F4540F4924B7D86C451C02D51E25A152F4540
1649	298	36	\N	\N	0102000020E610000002000000F4924B7D86C451C02D51E25A152F454078924B7D86C451C0DD47D15A152F4540
1650	298	39	\N	\N	0102000020E61000000200000078924B7D86C451C0DD47D15A152F45408B914B7D86C451C0E49CB05A152F4540
1651	298	40	\N	\N	0102000020E6100000030000008B914B7D86C451C0E49CB05A152F454006893E7D86C451C0CFF0148F132F454015A6327D86C451C084C1E9EB112F4540
1652	298	42	\N	\N	0102000020E61000000200000015A6327D86C451C084C1E9EB112F45401EA5327D86C451C025B1C7EB112F4540
1653	298	44	\N	\N	0102000020E6100000020000001EA5327D86C451C025B1C7EB112F4540E8A0327D86C451C0F82D33EB112F4540
1654	299	3	\N	\N	0102000020E61000000200000099BC849788C451C0804C40C00C2F45407D4B529788C451C0B7BDA1DD052F4540
1655	299	4	\N	\N	0102000020E6100000030000007D4B529788C451C0B7BDA1DD052F45409F95F5D688C451C00FDE377F052F4540768CE6D688C451C0F11A6072032F4540
1656	299	6	\N	\N	0102000020E610000003000000768CE6D688C451C0F11A6072032F4540091D1FBD88C451C0C09E274C032F4540497F1CBD88C451C097D1CAF0022F4540
1657	300	9	\N	\N	0102000020E61000000200000099BC849788C451C0804C40C00C2F454071EF5EA188C451C016C0DBCE0C2F4540
1658	300	11	\N	\N	0102000020E61000000200000071EF5EA188C451C016C0DBCE0C2F454002D501B588C451C0F4B4F8EB0C2F4540
1659	300	13	\N	\N	0102000020E61000000200000002D501B588C451C0F4B4F8EB0C2F4540ACB3374B89C451C08B05ADCA0D2F4540
1660	300	16	\N	\N	0102000020E610000002000000ACB3374B89C451C08B05ADCA0D2F45403C60D01A8AC451C0AC2776FE0E2F4540
1661	300	18	\N	\N	0102000020E6100000020000003C60D01A8AC451C0AC2776FE0E2F4540BAFB9C9A8AC451C0A30C6EFE0E2F4540
1662	301	7	\N	\N	0102000020E610000003000000C7A2CA0584C451C0C2B6988D112F454084DBBE0584C451C09DF3B6E90F2F4540978FBE0584C451C0F65F24DF0F2F4540
1663	301	13	\N	\N	0102000020E610000002000000978FBE0584C451C0F65F24DF0F2F45401B2212F983C451C098175ACC0F2F4540
1664	301	14	\N	\N	0102000020E6100000020000001B2212F983C451C098175ACC0F2F4540A70788ED81C451C0741923C40C2F4540
1665	302	8	\N	\N	0102000020E6100000020000001044CD0584C451C029595AEB112F4540953FCD0584C451C01991BAEA112F4540
1666	302	10	\N	\N	0102000020E610000002000000953FCD0584C451C01991BAEA112F4540AF3ECD0584C451C00E9F9AEA112F4540
1667	302	12	\N	\N	0102000020E610000002000000AF3ECD0584C451C00E9F9AEA112F4540BBA7CA0584C451C0BC3B498E112F4540
1668	302	14	\N	\N	0102000020E610000002000000BBA7CA0584C451C0BC3B498E112F4540AAA3CA0584C451C05864B88D112F4540
1669	302	16	\N	\N	0102000020E610000002000000AAA3CA0584C451C05864B88D112F4540C7A2CA0584C451C0C2B6988D112F4540
1670	303	25	\N	\N	0102000020E6100000020000004EF6E50584C451C0E36DBC5B152F4540ECF5E50584C451C012D1AE5B152F4540
1671	303	27	\N	\N	0102000020E610000002000000ECF5E50584C451C012D1AE5B152F45400CF5E50584C451C0D1948F5B152F4540
1672	303	30	\N	\N	0102000020E6100000020000000CF5E50584C451C0D1948F5B152F454033F3E50584C451C0DCC14D5B152F4540
1673	303	33	\N	\N	0102000020E61000000200000033F3E50584C451C0DCC14D5B152F45404AF2E50584C451C0874D2D5B152F4540
1674	303	36	\N	\N	0102000020E6100000020000004AF2E50584C451C0874D2D5B152F4540D3F1E50584C451C077A51C5B152F4540
1675	303	39	\N	\N	0102000020E610000002000000D3F1E50584C451C077A51C5B152F4540EDF0E50584C451C05BB3FC5A152F4540
1676	303	42	\N	\N	0102000020E610000002000000EDF0E50584C451C05BB3FC5A152F454080F0E50584C451C0C78AED5A152F4540
1677	303	45	\N	\N	0102000020E61000000200000080F0E50584C451C0C78AED5A152F45405DEEE50584C451C02E57A15A152F4540
1678	303	46	\N	\N	0102000020E6100000030000005DEEE50584C451C02E57A15A152F4540550BD90584C451C0011C3C8F132F45400449CD0584C451C056DE0AEC112F4540
1679	303	48	\N	\N	0102000020E6100000020000000449CD0584C451C056DE0AEC112F4540F344CD0584C451C0C6067AEB112F4540
1680	303	50	\N	\N	0102000020E610000002000000F344CD0584C451C0C6067AEB112F45401044CD0584C451C029595AEB112F4540
1681	304	16	\N	\N	0102000020E610000002000000A70788ED81C451C0741923C40C2F4540830088ED81C451C0C92822C30C2F4540
1682	304	19	\N	\N	0102000020E610000002000000830088ED81C451C0C92822C30C2F4540A2FE87ED81C451C04983DEC20C2F4540
1683	304	22	\N	\N	0102000020E610000002000000A2FE87ED81C451C04983DEC20C2F454072F287ED81C451C0641228C10C2F4540
1684	304	25	\N	\N	0102000020E61000000200000072F287ED81C451C0641228C10C2F454047F187ED81C451C0F6F2FDC00C2F4540
1685	304	28	\N	\N	0102000020E61000000200000047F187ED81C451C0F6F2FDC00C2F454069E557ED81C451C0C8163300062F4540
1686	304	29	\N	\N	0102000020E61000000300000069E557ED81C451C0C8163300062F4540D347AFAD81C451C0BF1CD1A1052F4540DAAD9FAD81C451C08256D26F032F4540
1687	304	31	\N	\N	0102000020E610000003000000DAAD9FAD81C451C08256D26F032F45407ABFFFC681C451C038CF2C4A032F45407949FDC681C451C085CC90F1022F4540
1688	304	32	\N	\N	0102000020E6100000020000007949FDC681C451C085CC90F1022F45408632FDC681C451C07F8956EE022F4540
1689	305	16	\N	\N	0102000020E610000002000000A70788ED81C451C0741923C40C2F4540D952443981C451C0CF2593CF0D2F4540
1690	305	19	\N	\N	0102000020E610000002000000D952443981C451C0CF2593CF0D2F4540A921A52681C451C0CBAE33EB0D2F4540
1691	305	20	\N	\N	0102000020E610000002000000A921A52681C451C0CBAE33EB0D2F4540EF3BE48B80C451C06EB8CAD00E2F4540
1692	305	23	\N	\N	0102000020E610000002000000EF3BE48B80C451C06EB8CAD00E2F4540393FA18180C451C0521404E00E2F4540
1693	305	25	\N	\N	0102000020E610000002000000393FA18180C451C0521404E00E2F4540805E006E80C451C0C1E922FD0E2F4540
1694	305	27	\N	\N	0102000020E610000002000000805E006E80C451C0C1E922FD0E2F4540BB815C6280C451C0DFCA670E0F2F4540
1695	305	32	\N	\N	0102000020E610000002000000BB815C6280C451C0DFCA670E0F2F4540A6F17DE37FC451C05E7C6F0E0F2F4540
1696	306	4	\N	\N	0102000020E61000000300000086FCBF2F84C451C05BE82C1E192F4540FFC5CB2F84C451C025AA0EC21A2F4540A2E6CB2F84C451C04C5399C61A2F4540
1697	306	6	\N	\N	0102000020E610000002000000A2E6CB2F84C451C04C5399C61A2F4540A1BB2A7387C451C0511B219D1F2F4540
1698	306	7	\N	\N	0102000020E610000002000000A1BB2A7387C451C0511B219D1F2F45401C92337387C451C0A9577BD3202F4540
1699	306	8	\N	\N	0102000020E6100000050000001C92337387C451C0A9577BD3202F4540065A468A87C451C059C5B0F5202F4540C100DED687C451C0FCF7ABF5202F45408459E3F387C451C07AE59DCA202F4540CD1C982688C451C054B69ACA202F4540
1700	307	10	\N	\N	0102000020E610000002000000C2AEBD2F84C451C0F2ED1BCC182F4540F3B2BD2F84C451C0E234B1CC182F4540
1701	307	12	\N	\N	0102000020E610000002000000F3B2BD2F84C451C0E234B1CC182F4540C1B3BD2F84C451C04AE8CDCC182F4540
1702	307	14	\N	\N	0102000020E610000002000000C1B3BD2F84C451C04AE8CDCC182F4540F9F7BF2F84C451C0D2C68A1D192F4540
1703	307	16	\N	\N	0102000020E610000002000000F9F7BF2F84C451C0D2C68A1D192F4540E4F8BF2F84C451C0947BAB1D192F4540
1704	307	18	\N	\N	0102000020E610000002000000E4F8BF2F84C451C0947BAB1D192F4540A7FBBF2F84C451C011D30D1E192F4540
1705	307	20	\N	\N	0102000020E610000002000000A7FBBF2F84C451C011D30D1E192F454086FCBF2F84C451C05BE82C1E192F4540
1706	308	23	\N	\N	0102000020E610000002000000B36325F982C451C0F9F8CC5B152F454082FCDD0983C451C0CB7A9774152F4540
1707	308	25	\N	\N	0102000020E61000000200000082FCDD0983C451C0CB7A9774152F45409FDF801D83C451C0FF73B491152F4540
1708	308	27	\N	\N	0102000020E6100000020000009FDF801D83C451C0FF73B491152F4540B40492A683C451C01364EC5C162F4540
1709	308	29	\N	\N	0102000020E610000002000000B40492A683C451C01364EC5C162F45404BE5B12F84C451C0DF2B3A28172F4540
1710	308	46	\N	\N	0102000020E6100000020000004BE5B12F84C451C0DF2B3A28172F4540C2AEBD2F84C451C0F2ED1BCC182F4540
1711	309	36	\N	\N	0102000020E61000000200000085DD832F5BC451C0CC83A6F6092F4540837B8D2F5BC451C0C1E0EF980B2F4540
1712	309	38	\N	\N	0102000020E610000002000000837B8D2F5BC451C0C1E0EF980B2F454039458E2F5BC451C0FA0F35BB0B2F4540
1713	309	40	\N	\N	0102000020E61000000200000039458E2F5BC451C0FA0F35BB0B2F45400A5C942F5BC451C0B7DC0BC40C2F4540
1714	309	41	\N	\N	0102000020E6100000020000000A5C942F5BC451C0B7DC0BC40C2F454077B7952F5BC451C0BD9B12FF0C2F4540
1715	309	44	\N	\N	0102000020E61000000200000077B7952F5BC451C0BD9B12FF0C2F45402D9FA12F5BC451C09D23DF040F2F4540
1716	309	45	\N	\N	0102000020E6100000020000002D9FA12F5BC451C09D23DF040F2F45406FCDA72F5BC451C0F471B111102F4540
1717	309	46	\N	\N	0102000020E6100000020000006FCDA72F5BC451C0F471B111102F4540DC99B02F5BC451C014036090112F4540
1718	309	48	\N	\N	0102000020E610000002000000DC99B02F5BC451C014036090112F4540669AB02F5BC451C08B737790112F4540
1719	309	50	\N	\N	0102000020E610000002000000669AB02F5BC451C08B737790112F4540B4C1B22F5BC451C085A521EE112F4540
1720	309	52	\N	\N	0102000020E610000002000000B4C1B22F5BC451C085A521EE112F45403DC2B22F5BC451C0FB1539EE112F4540
1721	309	54	\N	\N	0102000020E6100000020000003DC2B22F5BC451C0FB1539EE112F4540E695B62F5BC451C0FA31AA94122F4540
1722	309	57	\N	\N	0102000020E610000002000000E695B62F5BC451C0FA31AA94122F45405EF2B62F5BC451C04FFD5FA4122F4540
1723	309	60	\N	\N	0102000020E6100000020000005EF2B62F5BC451C04FFD5FA4122F454008F4B62F5BC451C0615BA8A4122F4540
1724	309	62	\N	\N	0102000020E61000000200000008F4B62F5BC451C0615BA8A4122F45404EFFC62F5BC451C04B0D795E152F4540
1725	309	65	\N	\N	0102000020E6100000020000004EFFC62F5BC451C04B0D795E152F45408CFFC62F5BC451C0A2BA835E152F4540
1726	309	68	\N	\N	0102000020E6100000020000008CFFC62F5BC451C0A2BA835E152F45401600C72F5BC451C0162B9B5E152F4540
1727	309	71	\N	\N	0102000020E6100000020000001600C72F5BC451C0162B9B5E152F45404301C72F5BC451C03635CE5E152F4540
1728	309	72	\N	\N	0102000020E6100000020000004301C72F5BC451C03635CE5E152F4540E32FC92F5BC451C060F2B6BD152F4540
1729	310	7	\N	\N	0102000020E6100000020000009AA97DDF58C451C0D676A197002F454095869FE558C451C0073F01AF002F4540
1730	310	9	\N	\N	0102000020E61000000200000095869FE558C451C0073F01AF002F454050060CC959C451C003E4DD11042F4540
1731	310	10	\N	\N	0102000020E61000000200000050060CC959C451C003E4DD11042F4540FC7C5E4E5AC451C0A48D0B0E062F4540
1732	310	13	\N	\N	0102000020E610000002000000FC7C5E4E5AC451C0A48D0B0E062F4540F096802F5BC451C0F20C2D68092F4540
1733	310	14	\N	\N	0102000020E610000002000000F096802F5BC451C0F20C2D68092F454085DD832F5BC451C0CC83A6F6092F4540
1734	311	19	\N	\N	0102000020E61000000200000076A25C89D2C451C05425B3D3092F4540E7E06A89D2C451C0BD5BB94C0B2F4540
1735	311	21	\N	\N	0102000020E610000002000000E7E06A89D2C451C0BD5BB94C0B2F4540AD957089D2C451C0ADBDC2E30B2F4540
1736	311	23	\N	\N	0102000020E610000002000000AD957089D2C451C0ADBDC2E30B2F4540A26C8389D2C451C086466ED60D2F4540
1737	311	26	\N	\N	0102000020E610000002000000A26C8389D2C451C086466ED60D2F4540946D8389D2C451C0265E87D60D2F4540
1738	311	28	\N	\N	0102000020E610000002000000946D8389D2C451C0265E87D60D2F45405A6E8389D2C451C0CCCF9BD60D2F4540
1739	311	29	\N	\N	0102000020E6100000020000005A6E8389D2C451C0CCCF9BD60D2F454071E09689D2C451C0859251D90F2F4540
1740	311	30	\N	\N	0102000020E61000000200000071E09689D2C451C0859251D90F2F45408670B289D2C451C07711E2B2122F4540
1741	311	33	\N	\N	0102000020E6100000020000008670B289D2C451C07711E2B2122F45405971B289D2C451C003DEF7B2122F4540
1742	311	36	\N	\N	0102000020E6100000020000005971B289D2C451C003DEF7B2122F45405975B289D2C451C0E6C061B3122F4540
1743	311	38	\N	\N	0102000020E6100000020000005975B289D2C451C0E6C061B3122F4540D676B289D2C451C0AA1C89B3122F4540
1744	312	8	\N	\N	0102000020E610000002000000AC41F338D0C451C05AC529D7002F45408A1A8D1CD1C451C0F13B4B44042F4540
1745	312	10	\N	\N	0102000020E6100000020000008A1A8D1CD1C451C0F13B4B44042F4540BB7E6E3BD1C451C0DA1A4DBB042F4540
1746	312	12	\N	\N	0102000020E610000002000000BB7E6E3BD1C451C0DA1A4DBB042F4540FD30C0F5D1C451C027EE5689072F4540
1747	312	15	\N	\N	0102000020E610000002000000FD30C0F5D1C451C027EE5689072F454029F95B89D2C451C0E0D531C2092F4540
1748	312	16	\N	\N	0102000020E61000000200000029F95B89D2C451C0E0D531C2092F454076A25C89D2C451C05425B3D3092F4540
1749	24	1	\N	\N	0102000020E6100000030000007A7507CD6AC451C02118C0CE202F4540B6CD7CE76AC451C053B5FAF5202F4540807414346BC451C0FB80F6F5202F4540
1750	40	1	\N	\N	0102000020E6100000020000009C5B66CC50C451C0B828F622302F4540091A67CC50C451C0926C3B45302F4540
1751	42	1	\N	\N	0102000020E610000002000000240BD8374DC451C090772123302F454085638BB84CC451C04E692723302F4540
1752	45	1	\N	\N	0102000020E6100000020000003DFFF36054C451C0DD215004302F45406F8332D354C451C05C8F4A04302F4540
1753	50	1	\N	\N	0102000020E610000002000000F7F1DC0844C451C0D5A6B0851C2F4540C39A808844C451C060FEAA851C2F4540
1754	51	1	\N	\N	0102000020E610000003000000F7B6E77B42C451C02C23C2851C2F4540EE91372343C451C0B3C9BA851C2F4540F7F1DC0844C451C0D5A6B0851C2F4540
1755	71	1	\N	\N	0102000020E6100000020000001249898745C451C0215B6765272F45401ABE8E7745C451C02923B64D272F4540
1756	75	1	\N	\N	0102000020E61000000200000086DE765D4EC451C03AE862BC0B2F4540C022765D4EC451C000B91D9A0B2F4540
1757	84	1	\N	\N	0102000020E610000004000000E62011BF50C451C0AAEB7BB9F62E45409F215A7A51C451C08B82A5A3F52E4540EC3B6C8653C451C06F3F8CA3F52E4540D2F49A5254C451C08A5382A3F52E4540
1758	102	1	\N	\N	0102000020E6100000030000002901E3155FC451C0681981871C2F45409DAC2D645EC451C007428A871C2F4540914C887E5DC451C02C0B96871C2F4540
1759	117	1	\N	\N	0102000020E610000002000000584FB8125CC451C00BD48388272F4540CCF5DF1A5CC451C0792C9B94272F4540
1760	121	1	\N	\N	0102000020E610000002000000310D07235CC451C0E2FF8288272F45409E58D9505CC451C0C63F8944272F4540
1761	122	1	\N	\N	0102000020E610000002000000CCF5DF1A5CC451C0792C9B94272F4540310D07235CC451C0E2FF8288272F4540
1762	155	1	\N	\N	0102000020E61000000200000097149084A0C451C03E08DE59152F4540DF9AB52FA2C451C07843C059152F4540
1763	172	1	\N	\N	0102000020E610000002000000074D3EC2D7C451C0AC5CBDD50D2F45407244F7F5D8C451C0994DA3D50D2F4540
1764	177	1	\N	\N	0102000020E610000002000000B54BF1D0D4C451C0C91A957B1C2F45405D679354D4C451C00B829F7B1C2F4540
1765	194	1	\N	\N	0102000020E610000002000000122F0A6DD3C451C0F7B0B147272F4540BBFB2B75D3C451C055D5BF53272F4540
1766	199	1	\N	\N	0102000020E610000002000000BBFB2B75D3C451C055D5BF53272F454071DE4C7DD3C451C00656B047272F4540
1767	201	1	\N	\N	0102000020E6100000020000009DDFBF54CAC451C0253200E50B2F45402852BA54CAC451C02FD0F64D0B2F4540
1768	205	1	\N	\N	0102000020E610000002000000F30CD9ABCBC451C09DDB3989FB2E45400CE0242BCCC451C06F822F89FB2E4540
1769	211	1	\N	\N	0102000020E610000002000000A3797787C4C451C036826B92012F45400C89F803C4C451C09EEC7592012F4540
1770	212	1	\N	\N	0102000020E610000003000000B8FACEB6C5C451C03A695392012F4540460293A2C5C451C080055592012F4540A3797787C4C451C036826B92012F4540
1771	213	1	\N	\N	0102000020E610000002000000C6947B2FC0C451C0DD5819AEFD2E45400C777A2FC0C451C00FC37997FD2E4540
1772	221	1	\N	\N	0102000020E6100000020000001959465BBBC451C04C1EBB851C2F45401C4579E0BBC451C0D0E1B0851C2F4540
\.


--
-- Data for Name: first_floor_edges_vertices_pgr; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.first_floor_edges_vertices_pgr (id, cnt, chk, ein, eout, the_geom) FROM stdin;
1	\N	\N	\N	\N	01010000A034BF0D00CCC6C444F70B3FC0283B51E7C38123C09A9999999999E93F
2	\N	\N	\N	\N	01010000A034BF0D00C4C1243DDC6F3EC0286CC2FEA5D625C09A9999999999E93F
3	\N	\N	\N	\N	01010000A034BF0D00CCC6C444F70B3FC0680F4036204A23C09A9999999999E93F
4	\N	\N	\N	\N	01010000A034BF0D0000714B1FBF8C3FC0807E2ADAF67913C09A9999999999E93F
5	\N	\N	\N	\N	01010000A034BF0D009C983119DFF43BC0386CC2FEA5D625C09A9999999999E93F
6	\N	\N	\N	\N	01010000A034BF0D009C939111C4583BC0680F4036204A23C09A9999999999E93F
7	\N	\N	\N	\N	01010000A034BF0D002C812E8413EB3BC0307C1B72A1D217C09A9999999999E93F
8	\N	\N	\N	\N	01010000A034BF0D009C939111C4583BC0583B51E7C38123C09A9999999999E93F
9	\N	\N	\N	\N	01010000A034BF0D006465FEE5ABC13AC0486CC2FEA5D625C09A9999999999E93F
10	\N	\N	\N	\N	01010000A034BF0D0068605EDE90253AC0F80D4036204A23C09A9999999999E93F
11	\N	\N	\N	\N	01010000A034BF0D00B02CD7C7B79639C05092C401C8C417C09A9999999999E93F
12	\N	\N	\N	\N	01010000A034BF0D0068605EDE90253AC0683B51E7C38123C09A9999999999E93F
13	\N	\N	\N	\N	01010000A034BF0D0068B4326F73253AC0486CC2FEA5D625C09A9999999999E93F
14	\N	\N	\N	\N	01010000A034BF0D004458A3AC7DFC38C0506CC2FEA5D625C09A9999999999E93F
15	\N	\N	\N	\N	01010000A034BF0D0084CBBC85C67038C0506CC2FEA5D625C09A9999999999E93F
16	\N	\N	\N	\N	01010000A034BF0D0094C61C7EABD437C0680F4036204A23C09A9999999999E93F
17	\N	\N	\N	\N	01010000A034BF0D0040084BD4A04237C080C0EE4E8ED117C09A9999999999E93F
18	\N	\N	\N	\N	01010000A034BF0D0094C61C7EABD437C0883B51E7C38123C09A9999999999E93F
19	\N	\N	\N	\N	01010000A034BF0D004498895293BD35C0606CC2FEA5D625C09A9999999999E93F
20	\N	\N	\N	\N	01010000A034BF0D005C93E94A782135C0680F4036204A23C09A9999999999E93F
21	\N	\N	\N	\N	01010000A034BF0D0088139A62CA7B33C0A0767CC5F1281CC09A9999999999E93F
22	\N	\N	\N	\N	01010000A034BF0D005C93E94A782135C0A83B51E7C38123C09A9999999999E93F
23	\N	\N	\N	\N	01010000A034BF0D0088AC901499AF33C060A1B065BEF31BC09A9999999999E93F
24	\N	\N	\N	\N	01010000A034BF0D00A4A8C7233CD733C090F98D16EB2A1CC09A9999999999E93F
25	\N	\N	\N	\N	01010000A034BF0D00E0F5E5E5601D34C010E4096880371AC09A9999999999E93F
26	\N	\N	\N	\N	01010000A034BF0D00D0CE647C4E4F32C0C063A72C027717C09A9999999999E93F
27	\N	\N	\N	\N	01010000A034BF0D00C043F5649C0133C0786CC2FEA5D625C09A9999999999E93F
28	\N	\N	\N	\N	01010000A034BF0D00082570794AC931C0786CC2FEA5D625C09A9999999999E93F
29	\N	\N	\N	\N	01010000A034BF0D0000B991AFCE3C31C0806CC2FEA5D625C09A9999999999E93F
30	\N	\N	\N	\N	01010000A034BF0D0024B4F1A7B3A030C0680F4036204A23C09A9999999999E93F
31	\N	\N	\N	\N	01010000A034BF0D001C51D44F0B0F30C0F0521D0805D017C09A9999999999E93F
32	\N	\N	\N	\N	01010000A034BF0D0024B4F1A7B3A030C0E03B51E7C38123C09A9999999999E93F
33	\N	\N	\N	\N	01010000A034BF0D0088D2CCD1059329C080B5B562C69525C09A9999999999E93F
34	\N	\N	\N	\N	01010000A034BF0D00609E71E1904427C080B5B562C69525C09A9999999999E93F
35	\N	\N	\N	\N	01010000A034BF0D00B08896D3608224C0184F4FFC5FAF27C09A9999999999E93F
36	\N	\N	\N	\N	01010000A034BF0D00107B24C261CF1BC0184F4FFC5FAF27C09A9999999999E93F
37	\N	\N	\N	\N	01010000A034BF0D00B0AB285BDEA319C0407B8399F92BFEBF9A9999999999E93F
38	\N	\N	\N	\N	01010000A034BF0D00B0AB285BDEA319C0C0DB85ACAD86FDBF9A9999999999E93F
39	\N	\N	\N	\N	01010000A034BF0D00B0AB285BDEA319C0C0CCCCCCCCCCFCBF9A9999999999E93F
40	\N	\N	\N	\N	01010000A034BF0D006079F527AB7011C0C0DB85ACAD86FDBF9A9999999999E93F
41	\N	\N	\N	\N	01010000A034BF0D0000C3E64694CDF4BF80D1E64694CDF4BF9A9999999999E93F
42	\N	\N	\N	\N	01010000A034BF0D008078F527AB7012C0C0DB85ACAD86FDBF9A9999999999E93F
43	\N	\N	\N	\N	01010000A034BF0D00F05DA33F68DE20C0407B8399F92BFEBF9A9999999999E93F
44	\N	\N	\N	\N	01010000A034BF0D001079B440D10C27C080F0E816D5DAF3BF9A9999999999E93F
45	\N	\N	\N	\N	01010000A034BF0D0070EF2DC7886B20C0407B8399F92BFEBF9A9999999999E93F
46	\N	\N	\N	\N	01010000A034BF0D0080B4213EB5C014C0681D93A2EBB927C09A9999999999E93F
47	\N	\N	\N	\N	01010000A034BF0D00000FDD6C5825E93F28897F828FFD20C09A9999999999E93F
48	\N	\N	\N	\N	01010000A034BF0D000010C12DEE49CFBF28897F828FFD20C09A9999999999E93F
49	\N	\N	\N	\N	01010000A034BF0D0040BDD35CC1B5F7BFE8968166ED1A20C09A9999999999E93F
50	\N	\N	\N	\N	01010000A034BF0D000000A10A9780793F28897F828FFD20C09A9999999999E93F
51	\N	\N	\N	\N	01010000A034BF0D0080235D8414FB08C0E8968166ED1A20C09A9999999999E93F
52	\N	\N	\N	\N	01010000A034BF0D0080F5B51E2CD5F0BFE088E89125971DC09A9999999999E93F
53	\N	\N	\N	\N	01010000A034BF0D0000172739EF64F5BF4034A69E5BEE16C09A9999999999E93F
54	\N	\N	\N	\N	01010000A034BF0D00C08C2C52A73CFCBF4034A69E5BEE16C09A9999999999E93F
55	\N	\N	\N	\N	01010000A034BF0D00004DF30EBA8406C04034A69E5BEE16C09A9999999999E93F
56	\N	\N	\N	\N	01010000A034BF0D008060E6C8A14C0FC0208876BC630013C09A9999999999E93F
57	\N	\N	\N	\N	01010000A034BF0D0040A9C743B6FA0EC080A98C83D4800EC09A9999999999E93F
58	\N	\N	\N	\N	01010000A034BF0D008060E6C8A14C0FC0301739B28C5C13C09A9999999999E93F
59	\N	\N	\N	\N	01010000A034BF0D00004DF30EBA8406C0208876BC630013C09A9999999999E93F
60	\N	\N	\N	\N	01010000A034BF0D00804EF30EBA8406C0C05495B43E710EC09A9999999999E93F
61	\N	\N	\N	\N	01010000A034BF0D00004DF30EBA8406C0301739B28C5C13C09A9999999999E93F
62	\N	\N	\N	\N	01010000A034BF0D00C08C2C52A73CFCBF208876BC630013C09A9999999999E93F
63	\N	\N	\N	\N	01010000A034BF0D00008E2C52A73CFCBFC05495B43E710EC09A9999999999E93F
64	\N	\N	\N	\N	01010000A034BF0D00C08C2C52A73CFCBF301739B28C5C13C09A9999999999E93F
65	\N	\N	\N	\N	01010000A034BF0D0000B15DBEEEBAE8BF301739B28C5C13C09A9999999999E93F
66	\N	\N	\N	\N	01010000A034BF0D000092B9B7F7D5E7BF80CB21856B3C13C09A9999999999E93F
67	\N	\N	\N	\N	01010000A034BF0D000092B9B7F7D5E7BF208876BC630013C09A9999999999E93F
68	\N	\N	\N	\N	01010000A034BF0D00007834CCA51DE7BF0078C184C2610EC09A9999999999E93F
69	\N	\N	\N	\N	01010000A034BF0D008034FF4EEED4E6BF301739B28C5C13C09A9999999999E93F
70	\N	\N	\N	\N	01010000A034BF0D00002DA4B8CFD2DBBFB0D5E8FACB1914C09A9999999999E93F
71	\N	\N	\N	\N	01010000A034BF0D008003FADFAE0FE6BFF04B3A66D0231CC09A9999999999E93F
72	\N	\N	\N	\N	01010000A034BF0D00000FDD6C5825E93F80CE57DF82481FC09A9999999999E93F
73	\N	\N	\N	\N	01010000A034BF0D0080B4213EB5C014C0409C1657F7752CC09A9999999999E93F
74	\N	\N	\N	\N	01010000A034BF0D00400781AB8F8B19C0FC189D930EA931C09A9999999999E93F
75	\N	\N	\N	\N	01010000A034BF0D0080B4213EB5C014C060D06649BB5E2CC09A9999999999E93F
76	\N	\N	\N	\N	01010000A034BF0D00400781AB8F8B19C0EC12A61DAB9433C09A9999999999E93F
77	\N	\N	\N	\N	01010000A034BF0D00400781AB8F8B19C0F0130479B94E35C09A9999999999E93F
78	\N	\N	\N	\N	01010000A034BF0D00404EBBD74E5A11C060E0DABC1EB735C09A9999999999E93F
79	\N	\N	\N	\N	01010000A034BF0D00001E7E3B0B74F4BF501707100D4036C09A9999999999E93F
80	\N	\N	\N	\N	01010000A034BF0D006050BBD74E5A12C060E0DABC1EB735C09A9999999999E93F
81	\N	\N	\N	\N	01010000A034BF0D00F05DA33F68DE20C09CD0749DE5AC35C09A9999999999E93F
82	\N	\N	\N	\N	01010000A034BF0D00308A991BCBF222C0A483A722F33E36C09A9999999999E93F
83	\N	\N	\N	\N	01010000A034BF0D00105FA33F685E20C09CD0749DE5AC35C09A9999999999E93F
84	\N	\N	\N	\N	01010000A034BF0D00F8CABD00F0FD26C0244846A9593E36C09A9999999999E93F
85	\N	\N	\N	\N	01010000A034BF0D0078B7711D6F3B21C0FC6CBB21A11A37C09A9999999999E93F
86	\N	\N	\N	\N	01010000A034BF0D00F05DA33F68DE20C0EC12A61DAB9433C09A9999999999E93F
87	\N	\N	\N	\N	01010000A034BF0D00D84014EA1F7127C054B90F6DE02934C09A9999999999E93F
88	\N	\N	\N	\N	01010000A034BF0D00105FA33F685E20C0EC12A61DAB9433C09A9999999999E93F
89	\N	\N	\N	\N	01010000A034BF0D00404EBBD74E5A11C0FC189D930EA931C09A9999999999E93F
90	\N	\N	\N	\N	01010000A034BF0D0040C6E66CB0FC02C084FF40F42A0533C09A9999999999E93F
91	\N	\N	\N	\N	01010000A034BF0D006050BBD74E5A12C0FC189D930EA931C09A9999999999E93F
92	\N	\N	\N	\N	01010000A034BF0D00808B683C3A23F1BF64CF6C460A3034C09A9999999999E93F
93	\N	\N	\N	\N	01010000A034BF0D004094A3A68EC6F4BF8433AFAC16F731C09A9999999999E93F
94	\N	\N	\N	\N	01010000A034BF0D00000E219E8222D2BFFC302EA7991931C09A9999999999E93F
95	\N	\N	\N	\N	01010000A034BF0D00802FA1F870ABE8BF747473F0CD5C32C09A9999999999E93F
96	\N	\N	\N	\N	01010000A034BF0D0078D5128EF50D25C018CFFEE9276E29C09A9999999999E93F
97	\N	\N	\N	\N	01010000A034BF0D0010DF512003302BC010E0328373FB20C09A9999999999E93F
98	\N	\N	\N	\N	01010000A034BF0D0010DF512003302BC02008B22A6B5D1FC09A9999999999E93F
99	\N	\N	\N	\N	01010000A034BF0D00406DC0E3AC1129C010E0328373FB20C09A9999999999E93F
100	\N	\N	\N	\N	01010000A034BF0D00906BECE3AC9126C0F8316F5BDB1420C09A9999999999E93F
101	\N	\N	\N	\N	01010000A034BF0D007045B886699629C010E0328373FB20C09A9999999999E93F
102	\N	\N	\N	\N	01010000A034BF0D00686694701B7827C0906DDB720E011DC09A9999999999E93F
103	\N	\N	\N	\N	01010000A034BF0D001084D38C95E328C040325D3A1A2A1AC09A9999999999E93F
104	\N	\N	\N	\N	01010000A034BF0D0028A17C8670EB26C0B078FB1B55E716C09A9999999999E93F
105	\N	\N	\N	\N	01010000A034BF0D0088AE9C064B0F26C0B078FB1B55E716C09A9999999999E93F
106	\N	\N	\N	\N	01010000A034BF0D00E06C256DB1F523C0B078FB1B55E716C09A9999999999E93F
107	\N	\N	\N	\N	01010000A034BF0D00E06C256DB1F523C0F0F826E7590B13C09A9999999999E93F
108	\N	\N	\N	\N	01010000A034BF0D00C06C256DB1F523C0606A3F6271870EC09A9999999999E93F
109	\N	\N	\N	\N	01010000A034BF0D00E06C256DB1F523C0A086E9DC826713C09A9999999999E93F
110	\N	\N	\N	\N	01010000A034BF0D0088E0DC5CA2C321C0F0F826E7590B13C09A9999999999E93F
111	\N	\N	\N	\N	01010000A034BF0D006090243E1DD821C02099CA851A970EC09A9999999999E93F
112	\N	\N	\N	\N	01010000A034BF0D0088E0DC5CA2C321C0A086E9DC826713C09A9999999999E93F
113	\N	\N	\N	\N	01010000A034BF0D0088AE9C064B0F26C0F0F826E7590B13C09A9999999999E93F
114	\N	\N	\N	\N	01010000A034BF0D00A0AE9C064B0F26C0A026A42F30870EC09A9999999999E93F
115	\N	\N	\N	\N	01010000A034BF0D0088AE9C064B0F26C0A086E9DC826713C09A9999999999E93F
116	\N	\N	\N	\N	01010000A034BF0D00307CAFA8562828C050F726E7590B13C09A9999999999E93F
117	\N	\N	\N	\N	01010000A034BF0D0078DEA186893028C0C032422BF4FA12C09A9999999999E93F
118	\N	\N	\N	\N	01010000A034BF0D00280AB6A6490728C0A086E9DC826713C09A9999999999E93F
119	\N	\N	\N	\N	01010000A034BF0D00688875DFD06628C0A086E9DC826713C09A9999999999E93F
120	\N	\N	\N	\N	01010000A034BF0D00688C0E9784C628C0104151638BFE13C09A9999999999E93F
121	\N	\N	\N	\N	01010000A034BF0D00C0409464BC3828C050F726E7590B13C09A9999999999E93F
122	\N	\N	\N	\N	01010000A034BF0D00700AB2397E0228C0A0D1B7C8D7ED0DC09A9999999999E93F
123	\N	\N	\N	\N	01010000A034BF0D00A85F773F685E23C0F8316F5BDB1420C09A9999999999E93F
124	\N	\N	\N	\N	01010000A034BF0D00082570794AC931C068550ABE186B28C09A9999999999E93F
125	\N	\N	\N	\N	01010000A034BF0D005472A2F7BBC930C0D0553F5BCF832BC09A9999999999E93F
126	\N	\N	\N	\N	01010000A034BF0D00082570794AC931C0289D3316882B28C09A9999999999E93F
127	\N	\N	\N	\N	01010000A034BF0D00906AF0AF2EA330C03418283FC22731C09A9999999999E93F
128	\N	\N	\N	\N	01010000A034BF0D005847053DAA6C2FC0284FC115B2242AC09A9999999999E93F
129	\N	\N	\N	\N	01010000A034BF0D00C043F5649C0133C068550ABE186B28C09A9999999999E93F
130	\N	\N	\N	\N	01010000A034BF0D00407F0EE7231034C0A83B7ACCFEAB2BC09A9999999999E93F
131	\N	\N	\N	\N	01010000A034BF0D00C043F5649C0133C0289D3316882B28C09A9999999999E93F
132	\N	\N	\N	\N	01010000A034BF0D00F80FE594552334C0541C6620062731C09A9999999999E93F
133	\N	\N	\N	\N	01010000A034BF0D003C0FFB33E41235C0284FC115B2242AC09A9999999999E93F
134	\N	\N	\N	\N	01010000A034BF0D004458A3AC7DFC38C068550ABE186B28C09A9999999999E93F
135	\N	\N	\N	\N	01010000A034BF0D00D818A880BDE937C0286F9AAF32AA2BC09A9999999999E93F
136	\N	\N	\N	\N	01010000A034BF0D004458A3AC7DFC38C0289D3316882B28C09A9999999999E93F
137	\N	\N	\N	\N	01010000A034BF0D002C4318C888D637C09C894580782A31C09A9999999999E93F
138	\N	\N	\N	\N	01010000A034BF0D009CA24B2517E636C0284FC115B2242AC09A9999999999E93F
139	\N	\N	\N	\N	01010000A034BF0D0068B4326F73253AC068550ABE186B28C09A9999999999E93F
140	\N	\N	\N	\N	01010000A034BF0D0024DF7C443B433BC01095F020C7AB2BC09A9999999999E93F
141	\N	\N	\N	\N	01010000A034BF0D0068B4326F73253AC0289D3316882B28C09A9999999999E93F
142	\N	\N	\N	\N	01010000A034BF0D0004F6522C64563BC074355418BA2931C09A9999999999E93F
143	\N	\N	\N	\N	01010000A034BF0D00C83B1535084B3CC0F84C7E6C9B1C2AC09A9999999999E93F
144	\N	\N	\N	\N	01010000A034BF0D00F4F457700FA33FC0286CC2FEA5D625C09A9999999999E93F
145	\N	\N	\N	\N	01010000A034BF0D00566393BE161540C0286CC2FEA5D625C09A9999999999E93F
146	\N	\N	\N	\N	01010000A034BF0D0078E87E10CFB340C0186CC2FEA5D625C09A9999999999E93F
147	\N	\N	\N	\N	01010000A034BF0D0036815F3DB26C43C0F86BC2FEA5D625C09A9999999999E93F
148	\N	\N	\N	\N	01010000A034BF0D007CF02BD09FA643C0F86BC2FEA5D625C09A9999999999E93F
149	\N	\N	\N	\N	01010000A034BF0D00D21AF9D64B0644C0F06BC2FEA5D625C09A9999999999E93F
150	\N	\N	\N	\N	01010000A034BF0D007EA01896F95A44C0E86BC2FEA5D625C09A9999999999E93F
151	\N	\N	\N	\N	01010000A034BF0D000A4E2C0A7F3945C0E06BC2FEA5D625C09A9999999999E93F
152	\N	\N	\N	\N	01010000A034BF0D00680B822BC0EC46C0C86BC2FEA5D625C09A9999999999E93F
153	\N	\N	\N	\N	01010000A034BF0D00221156A0D03E47C0C86BC2FEA5D625C09A9999999999E93F
154	\N	\N	\N	\N	01010000A034BF0D00A21559CF30AA47C0C06BC2FEA5D625C09A9999999999E93F
155	\N	\N	\N	\N	01010000A034BF0D00564489D303F247C0C06BC2FEA5D625C09A9999999999E93F
156	\N	\N	\N	\N	01010000A034BF0D0082B49270E59F4AC0986BC2FEA5D625C09A9999999999E93F
157	\N	\N	\N	\N	01010000A034BF0D004E6DE562C6E74AC0986BC2FEA5D625C09A9999999999E93F
158	\N	\N	\N	\N	01010000A034BF0D001A4E2C0A7F394BC0906BC2FEA5D625C09A9999999999E93F
159	\N	\N	\N	\N	01010000A034BF0D00BEAAEF396A984BC0906BC2FEA5D625C09A9999999999E93F
160	\N	\N	\N	\N	01010000A034BF0D0086B49270E55F4CC0886BC2FEA5D625C09A9999999999E93F
161	\N	\N	\N	\N	01010000A034BF0D00BE963790A6FC4DC0982FD38DE89425C09A9999999999E93F
162	\N	\N	\N	\N	01010000A034BF0D0071E8E793CF7950C058FC8391539327C09A9999999999E93F
163	\N	\N	\N	\N	01010000A034BF0D0009E94918F3B950C070E8FB28F59F27C09A9999999999E93F
164	\N	\N	\N	\N	01010000A034BF0D000B215CFFDAE050C070E8FB28F59F27C09A9999999999E93F
165	\N	\N	\N	\N	01010000A034BF0D0005B2C63F7EA051C070E8FB28F59F27C09A9999999999E93F
166	\N	\N	\N	\N	01010000A034BF0D0005B2C63F7EA051C0D076C63FED8E29C09A9999999999E93F
167	\N	\N	\N	\N	01010000A034BF0D00CBB62738E4E851C070E8FB28F59F27C09A9999999999E93F
168	\N	\N	\N	\N	01010000A034BF0D0095208A849EF351C070E8FB28F59F27C09A9999999999E93F
169	\N	\N	\N	\N	01010000A034BF0D000D40A11DB16152C0F8BDA57F49EC2AC09A9999999999E93F
170	\N	\N	\N	\N	01010000A034BF0D000D40A11DB16152C098378F0411B52FC09A9999999999E93F
171	\N	\N	\N	\N	01010000A034BF0D0015AF5FB3E79052C0F8BDA57F49EC2AC09A9999999999E93F
172	\N	\N	\N	\N	01010000A034BF0D007FDC7F2D95B752C0F8BDA57F49EC2AC09A9999999999E93F
173	\N	\N	\N	\N	01010000A034BF0D0071CFCA12276252C0D8AB83DC21FE20C09A9999999999E93F
174	\N	\N	\N	\N	01010000A034BF0D0071CFCA12276252C0B05F05658B5D1FC09A9999999999E93F
175	\N	\N	\N	\N	01010000A034BF0D00755CA765852252C0D8AB83DC21FE20C09A9999999999E93F
176	\N	\N	\N	\N	01010000A034BF0D0041E5377191D151C0E8E21A80081520C09A9999999999E93F
177	\N	\N	\N	\N	01010000A034BF0D0071CFCA12273252C0D8AB83DC21FE20C09A9999999999E93F
178	\N	\N	\N	\N	01010000A034BF0D00BDE1A681206D51C0E8E21A80081520C09A9999999999E93F
179	\N	\N	\N	\N	01010000A034BF0D006D1D9B4B54EF51C0D088E7334CAF1DC09A9999999999E93F
180	\N	\N	\N	\N	01010000A034BF0D001D1F5481CC0352C0E06D57D8C8671CC09A9999999999E93F
181	\N	\N	\N	\N	01010000A034BF0D00A18F30A7BFDD51C0B02AC32D53D816C09A9999999999E93F
182	\N	\N	\N	\N	01010000A034BF0D006D6DBFB4A2C051C0B02AC32D53D816C09A9999999999E93F
183	\N	\N	\N	\N	01010000A034BF0D00398590816F7D51C0B02AC32D53D816C09A9999999999E93F
184	\N	\N	\N	\N	01010000A034BF0D00398590816F7D51C0D06BAE083BFC12C09A9999999999E93F
185	\N	\N	\N	\N	01010000A034BF0D00118590816F7D51C0A0119B78979B0EC09A9999999999E93F
186	\N	\N	\N	\N	01010000A034BF0D00398590816F7D51C080F870FE635813C09A9999999999E93F
187	\N	\N	\N	\N	01010000A034BF0D00D33D983A013851C0D06BAE083BFC12C09A9999999999E93F
188	\N	\N	\N	\N	01010000A034BF0D005F33C196903A51C0E03EA86C0E910EC09A9999999999E93F
189	\N	\N	\N	\N	01010000A034BF0D00D33D983A013851C080F870FE635813C09A9999999999E93F
190	\N	\N	\N	\N	01010000A034BF0D006D6DBFB4A2C051C0D06BAE083BFC12C09A9999999999E93F
191	\N	\N	\N	\N	01010000A034BF0D004F6DBFB4A2C051C060119B78979B0EC09A9999999999E93F
192	\N	\N	\N	\N	01010000A034BF0D006D6DBFB4A2C051C080F870FE635813C09A9999999999E93F
193	\N	\N	\N	\N	01010000A034BF0D00D34E483C5E0552C080F870FE635813C09A9999999999E93F
194	\N	\N	\N	\N	01010000A034BF0D001D5111D6630652C0E0D3E0610A4813C09A9999999999E93F
195	\N	\N	\N	\N	01010000A034BF0D001D5111D6630652C02069AE083BFC12C09A9999999999E93F
196	\N	\N	\N	\N	01010000A034BF0D00475BE879D40352C060AB1840CD9B0EC09A9999999999E93F
197	\N	\N	\N	\N	01010000A034BF0D006753DA6F690752C080F870FE635813C09A9999999999E93F
198	\N	\N	\N	\N	01010000A034BF0D00898BBC2C391652C0904A640F871D14C09A9999999999E93F
199	\N	\N	\N	\N	01010000A034BF0D0005215CFFDAE050C0308D033138A42CC09A9999999999E93F
200	\N	\N	\N	\N	01010000A034BF0D009B9DC8D5A9C550C0B8C98A2B7DAA33C09A9999999999E93F
201	\N	\N	\N	\N	01010000A034BF0D0007215CFFDAE050C0C8269DCAD13D2CC09A9999999999E93F
202	\N	\N	\N	\N	01010000A034BF0D00C95671C5106C50C0B47605ED85B833C09A9999999999E93F
203	\N	\N	\N	\N	01010000A034BF0D0039548F320E1C51C0B8C98A2B7DAA33C09A9999999999E93F
204	\N	\N	\N	\N	01010000A034BF0D008B99DDEA2C5551C0B897E291E30034C09A9999999999E93F
205	\N	\N	\N	\N	01010000A034BF0D0039548F320E0C51C0B8C98A2B7DAA33C09A9999999999E93F
206	\N	\N	\N	\N	01010000A034BF0D00B9893B5B231252C02400ED43553733C09A9999999999E93F
207	\N	\N	\N	\N	01010000A034BF0D0039548F320E2C51C000AD1B735EA534C09A9999999999E93F
208	\N	\N	\N	\N	01010000A034BF0D00B76D2518584C50C00C73BC8BE09E31C09A9999999999E93F
209	\N	\N	\N	\N	01010000A034BF0D0027715965B01550C00C73BC8BE09E31C09A9999999999E93F
210	\N	\N	\N	\N	01010000A034BF0D00FACCDAAFEF344FC0CCE03282BCF032C09A9999999999E93F
211	\N	\N	\N	\N	01010000A034BF0D003DC11584372650C00C73BC8BE09E31C09A9999999999E93F
212	\N	\N	\N	\N	01010000A034BF0D007266B89BEF344FC0B00C1CCD67F832C09A9999999999E93F
213	\N	\N	\N	\N	01010000A034BF0D002ACE8A1230C74EC0F831B78AF12A32C09A9999999999E93F
214	\N	\N	\N	\N	01010000A034BF0D00EA7130D51B424EC06C651F7CF14A31C09A9999999999E93F
215	\N	\N	\N	\N	01010000A034BF0D0002377E00BD514EC0747176ECFA1133C09A9999999999E93F
216	\N	\N	\N	\N	01010000A034BF0D00B76D2518584C50C0CC4FF22413E231C09A9999999999E93F
217	\N	\N	\N	\N	01010000A034BF0D0085DC36B23D9950C018C2720549FE20C09A9999999999E93F
218	\N	\N	\N	\N	01010000A034BF0D00B626740340974DC02084700FA3F820C09A9999999999E93F
219	\N	\N	\N	\N	01010000A034BF0D00A2A11379631F4EC02084700FA3F820C09A9999999999E93F
220	\N	\N	\N	\N	01010000A034BF0D000A196671F6C14EC0C035E923800A20C09A9999999999E93F
221	\N	\N	\N	\N	01010000A034BF0D007A382FBFE7FD4DC02084700FA3F820C09A9999999999E93F
222	\N	\N	\N	\N	01010000A034BF0D003ADBB40582894FC0C035E923800A20C09A9999999999E93F
223	\N	\N	\N	\N	01010000A034BF0D007E87972A08874EC090AF1EB1B49E1DC09A9999999999E93F
224	\N	\N	\N	\N	01010000A034BF0D003637CF3EBAA54EC050D23B5DDCBD16C09A9999999999E93F
225	\N	\N	\N	\N	01010000A034BF0D00C2F75E5DC0E54EC050D23B5DDCBD16C09A9999999999E93F
226	\N	\N	\N	\N	01010000A034BF0D0032C8BCC3266C4FC050D23B5DDCBD16C09A9999999999E93F
227	\N	\N	\N	\N	01010000A034BF0D00A281797AB7F54FC040599F9BB6E112C09A9999999999E93F
228	\N	\N	\N	\N	01010000A034BF0D001A9627C298F04FC0808FD5649B470EC09A9999999999E93F
229	\N	\N	\N	\N	01010000A034BF0D009E81797AB7F54FC030EA6191DF3D13C09A9999999999E93F
230	\N	\N	\N	\N	01010000A034BF0D0046C8BCC3266C4FC040599F9BB6E112C09A9999999999E93F
231	\N	\N	\N	\N	01010000A034BF0D005EC8BCC3266C4FC040B905E4E1660EC09A9999999999E93F
232	\N	\N	\N	\N	01010000A034BF0D0042C8BCC3266C4FC030EA6191DF3D13C09A9999999999E93F
233	\N	\N	\N	\N	01010000A034BF0D00D6F75E5DC0E54EC040599F9BB6E112C09A9999999999E93F
234	\N	\N	\N	\N	01010000A034BF0D00E6F75E5DC0E54EC0C0B805E4E1660EC09A9999999999E93F
235	\N	\N	\N	\N	01010000A034BF0D00D2F75E5DC0E54EC030EA6191DF3D13C09A9999999999E93F
236	\N	\N	\N	\N	01010000A034BF0D00FAF10F4A34644EC040599F9BB6E112C09A9999999999E93F
237	\N	\N	\N	\N	01010000A034BF0D0026C4F309175E4EC0C0EDDBB4107B0EC09A9999999999E93F
238	\N	\N	\N	\N	01010000A034BF0D00FAF10F4A34644EC030EA6191DF3D13C09A9999999999E93F
239	\N	\N	\N	\N	01010000A034BF0D00662FF341625F4EC0D0EEFB6B85611CC09A9999999999E93F
240	\N	\N	\N	\N	01010000A034BF0D00B626740340974DC0B078244F36981FC09A9999999999E93F
241	\N	\N	\N	\N	01010000A034BF0D00DAB1C2ECD7114CC0680F4036204A23C09A9999999999E93F
242	\N	\N	\N	\N	01010000A034BF0D00F2BA11D6325C4CC0B0790C41C7AC17C09A9999999999E93F
243	\N	\N	\N	\N	01010000A034BF0D00DAB1C2ECD7114CC0F03951E7C38123C09A9999999999E93F
244	\N	\N	\N	\N	01010000A034BF0D00BEAAEF396A984BC068550ABE186B28C09A9999999999E93F
245	\N	\N	\N	\N	01010000A034BF0D002E4C9853B3FE4BC0D8D9AC243D842BC09A9999999999E93F
246	\N	\N	\N	\N	01010000A034BF0D00BEAAEF396A984BC0289D3316882B28C09A9999999999E93F
247	\N	\N	\N	\N	01010000A034BF0D00121A1B61E1114CC024F45A91932B31C09A9999999999E93F
248	\N	\N	\N	\N	01010000A034BF0D008A372226107D4CC068DDA7BF7C272AC09A9999999999E93F
249	\N	\N	\N	\N	01010000A034BF0D00724B5C8671EB4AC0D80E4036204A23C09A9999999999E93F
250	\N	\N	\N	\N	01010000A034BF0D00D6723B71F3314BC03039B25380A317C09A9999999999E93F
251	\N	\N	\N	\N	01010000A034BF0D00724B5C8671EB4AC0103A51E7C38123C09A9999999999E93F
252	\N	\N	\N	\N	01010000A034BF0D004E6DE562C6E74AC068550ABE186B28C09A9999999999E93F
253	\N	\N	\N	\N	01010000A034BF0D007AE91EFC805B4AC0A8281A828AAB2BC09A9999999999E93F
254	\N	\N	\N	\N	01010000A034BF0D004E6DE562C6E74AC0289D3316882B28C09A9999999999E93F
255	\N	\N	\N	\N	01010000A034BF0D000AC43961E1514AC0A49DDFC7092B31C09A9999999999E93F
256	\N	\N	\N	\N	01010000A034BF0D008A7B5F7BABDA49C060CAFCF650272AC09A9999999999E93F
257	\N	\N	\N	\N	01010000A034BF0D00DAB1C2ECD7514AC0680F4036204A23C09A9999999999E93F
258	\N	\N	\N	\N	01010000A034BF0D00E2709892A7074AC07048720F2BAD17C09A9999999999E93F
259	\N	\N	\N	\N	01010000A034BF0D00DAB1C2ECD7514AC0183A51E7C38123C09A9999999999E93F
260	\N	\N	\N	\N	01010000A034BF0D00564489D303F247C068550ABE186B28C09A9999999999E93F
261	\N	\N	\N	\N	01010000A034BF0D00AE1C522FB46E48C03882FAF9A6AA2BC09A9999999999E93F
262	\N	\N	\N	\N	01010000A034BF0D00564489D303F247C0289D3316882B28C09A9999999999E93F
263	\N	\N	\N	\N	01010000A034BF0D006E2AA0C7477848C03CA01D91932B31C09A9999999999E93F
264	\N	\N	\N	\N	01010000A034BF0D003A741992C2EF48C060CAFCF650272AC09A9999999999E93F
265	\N	\N	\N	\N	01010000A034BF0D003E1829533EF847C0680F4036204A23C09A9999999999E93F
266	\N	\N	\N	\N	01010000A034BF0D002A80F0CB5B7848C0B070F6186B1D1AC09A9999999999E93F
267	\N	\N	\N	\N	01010000A034BF0D003E1829533EF847C0583A51E7C38123C09A9999999999E93F
268	\N	\N	\N	\N	01010000A034BF0D00221156A0D03E47C068550ABE186B28C09A9999999999E93F
269	\N	\N	\N	\N	01010000A034BF0D0012360887E6C146C0C88F0EF08DAB2BC09A9999999999E93F
270	\N	\N	\N	\N	01010000A034BF0D00221156A0D03E47C0289D3316882B28C09A9999999999E93F
271	\N	\N	\N	\N	01010000A034BF0D007A9ABDC747B846C0C47D1AC8092B31C09A9999999999E93F
272	\N	\N	\N	\N	01010000A034BF0D0012890472084146C00067F7372B272AC09A9999999999E93F
273	\N	\N	\N	\N	01010000A034BF0D00020E52AFCD3A47C0680F4036204A23C09A9999999999E93F
274	\N	\N	\N	\N	01010000A034BF0D0036F00DCC5BB846C0D09EFDF7511E1AC09A9999999999E93F
275	\N	\N	\N	\N	01010000A034BF0D00020E52AFCD3A47C0683A51E7C38123C09A9999999999E93F
276	\N	\N	\N	\N	01010000A034BF0D00724B5C8671EB44C0680F4036204A23C09A9999999999E93F
277	\N	\N	\N	\N	01010000A034BF0D008E522D8DDA6A45C0B0E176D36AB215C09A9999999999E93F
278	\N	\N	\N	\N	01010000A034BF0D00724B5C8671EB44C0A03A51E7C38123C09A9999999999E93F
279	\N	\N	\N	\N	01010000A034BF0D007EA01896F95A44C068550ABE186B28C09A9999999999E93F
280	\N	\N	\N	\N	01010000A034BF0D0046693BBA19D544C0001B068CA3AA2BC09A9999999999E93F
281	\N	\N	\N	\N	01010000A034BF0D007EA01896F95A44C0289D3316882B28C09A9999999999E93F
282	\N	\N	\N	\N	01010000A034BF0D00E200242EAEDE44C020C0E290932B31C09A9999999999E93F
283	\N	\N	\N	\N	01010000A034BF0D007A334168325645C00067F7372B272AC09A9999999999E93F
284	\N	\N	\N	\N	01010000A034BF0D003E1829533EB843C0680F4036204A23C09A9999999999E93F
285	\N	\N	\N	\N	01010000A034BF0D00D07375614F4144C0F025328ABFAD15C09A9999999999E93F
286	\N	\N	\N	\N	01010000A034BF0D003E1829533EB843C0C03A51E7C38123C09A9999999999E93F
287	\N	\N	\N	\N	01010000A034BF0D007CF02BD09FA643C068550ABE186B28C09A9999999999E93F
288	\N	\N	\N	\N	01010000A034BF0D00DE9E06145A2843C04086AE5559AB2BC09A9999999999E93F
289	\N	\N	\N	\N	01010000A034BF0D007CF02BD09FA643C0289D3316882B28C09A9999999999E93F
290	\N	\N	\N	\N	01010000A034BF0D00225BD42DAC1E43C040327BC7052B31C09A9999999999E93F
291	\N	\N	\N	\N	01010000A034BF0D00E080118D64A742C098AC910A02272AC09A9999999999E93F
292	\N	\N	\N	\N	01010000A034BF0D00A67E8FB9A41E43C0680F4036204A23C09A9999999999E93F
293	\N	\N	\N	\N	01010000A034BF0D00001B489B83D442C0407E2B428ED117C09A9999999999E93F
294	\N	\N	\N	\N	01010000A034BF0D00A67E8FB9A41E43C0D03A51E7C38123C09A9999999999E93F
295	\N	\N	\N	\N	01010000A034BF0D0078E87E10CFB340C068550ABE186B28C09A9999999999E93F
296	\N	\N	\N	\N	01010000A034BF0D002A29A0372B3B41C030C8CC6460AC2BC09A9999999999E93F
297	\N	\N	\N	\N	01010000A034BF0D0078E87E10CFB340C0289D3316882B28C09A9999999999E93F
298	\N	\N	\N	\N	01010000A034BF0D00A018A184B04441C048533AC48B2931C09A9999999999E93F
299	\N	\N	\N	\N	01010000A034BF0D007C08011AA3BC41C098AC910A02272AC09A9999999999E93F
300	\N	\N	\N	\N	01010000A034BF0D00566393BE161540C068550ABE186B28C09A9999999999E93F
301	\N	\N	\N	\N	01010000A034BF0D00F48BE788A21C3FC0303CC6B005AA2BC09A9999999999E93F
302	\N	\N	\N	\N	01010000A034BF0D00566393BE161540C0289D3316882B28C09A9999999999E93F
303	\N	\N	\N	\N	01010000A034BF0D006C3C570A65093FC03C29AF39862A31C09A9999999999E93F
304	\N	\N	\N	\N	01010000A034BF0D00F0CC227D24163EC0F84C7E6C9B1C2AC09A9999999999E93F
305	\N	\N	\N	\N	01010000A034BF0D00FEFCFB3B951F40C0680F4036204A23C09A9999999999E93F
306	\N	\N	\N	\N	01010000A034BF0D000ACEA353A31E41C0D038D4A7392C1CC09A9999999999E93F
307	\N	\N	\N	\N	01010000A034BF0D00FEFCFB3B951F40C0183B51E7C38123C09A9999999999E93F
308	\N	\N	\N	\N	01010000A034BF0D00609E71E1904427C090039A7CEE912DC09A9999999999E93F
309	\N	\N	\N	\N	01010000A034BF0D00F87D8A907CF124C05807A30C40F631C09A9999999999E93F
310	\N	\N	\N	\N	01010000A034BF0D00CBB62738E4E851C0308D033138A42DC09A9999999999E93F
311	\N	\N	\N	\N	01010000A034BF0D0089855B35799E51C044E93BEB08DE31C09A9999999999E93F
312	\N	\N	\N	\N	01010000A034BF0D00B692D5108DFD4DC000245E4E0E412CC00000000000000840
313	\N	\N	\N	\N	01010000A034BF0D00D24212692D984DC070E450AF8FAB2AC00000000000000840
314	\N	\N	\N	\N	01010000A034BF0D00D24212692D984DC0880F09DE84662AC00000000000000840
315	\N	\N	\N	\N	01010000A034BF0D00E675459C60B34DC090D498BCE34728C00000000000000840
316	\N	\N	\N	\N	01010000A034BF0D00E675459C60B34DC0980705A102E425C00000000000000840
317	\N	\N	\N	\N	01010000A034BF0D00E675459C60B34DC0E8665D4DB8C728C00000000000000840
318	\N	\N	\N	\N	01010000A034BF0D00E2C9D754D2004EC068EA1A4C939D25C00000000000000840
319	\N	\N	\N	\N	01010000A034BF0D00AEC273CF07EC4FC078C1BEBCD0A727C00000000000000840
320	\N	\N	\N	\N	01010000A034BF0D00BB735325F37350C078C1BEBCD0A727C00000000000000840
321	\N	\N	\N	\N	01010000A034BF0D0007215CFFDAE050C0A8AAA3CFEFAF27C00000000000000840
322	\N	\N	\N	\N	01010000A034BF0D0039548F320E1C51C024CA8A2B7DAA33C00000000000000840
323	\N	\N	\N	\N	01010000A034BF0D008B99DDEA2C5551C0B897E291E30034C00000000000000840
324	\N	\N	\N	\N	01010000A034BF0D0039548F320E0C51C024CA8A2B7DAA33C00000000000000840
325	\N	\N	\N	\N	01010000A034BF0D0007215CFFDAE050C08842CD9CEABD2CC00000000000000840
326	\N	\N	\N	\N	01010000A034BF0D0007215CFFDAE050C0A882E09D5E5C2CC00000000000000840
327	\N	\N	\N	\N	01010000A034BF0D00B9893B5B231252C02400ED43553733C00000000000000840
328	\N	\N	\N	\N	01010000A034BF0D0039548F320E2C51C000AD1B735EA534C00000000000000840
329	\N	\N	\N	\N	01010000A034BF0D003B548F320E5451C0A8AAA3CFEFAF27C00000000000000840
330	\N	\N	\N	\N	01010000A034BF0D0061EC4408028D51C0A8AAA3CFEFAF27C00000000000000840
331	\N	\N	\N	\N	01010000A034BF0D00F14DD1D4FB9F51C008321BE2052929C00000000000000840
332	\N	\N	\N	\N	01010000A034BF0D009D1B45160EF251C098D3FF5EB2A527C00000000000000840
333	\N	\N	\N	\N	01010000A034BF0D00C9129CB2916052C090BCA57F49EC2AC00000000000000840
334	\N	\N	\N	\N	01010000A034BF0D00C9129CB2916052C0F875EB3545AC2FC00000000000000840
335	\N	\N	\N	\N	01010000A034BF0D00C9129CB2919052C090BCA57F49EC2AC00000000000000840
336	\N	\N	\N	\N	01010000A034BF0D0083DC7F2D95B752C090BCA57F49EC2AC00000000000000840
337	\N	\N	\N	\N	01010000A034BF0D001DB0D345E36152C0C8AB83DC21FE20C00000000000000840
338	\N	\N	\N	\N	01010000A034BF0D001DB0D345E36152C060A81CDBA65D1FC00000000000000840
339	\N	\N	\N	\N	01010000A034BF0D00755CA765852252C0C8AB83DC21FE20C00000000000000840
340	\N	\N	\N	\N	01010000A034BF0D0041E5377191D151C0E8E21A80081520C00000000000000840
341	\N	\N	\N	\N	01010000A034BF0D00755CA765853252C0C8AB83DC21FE20C00000000000000840
342	\N	\N	\N	\N	01010000A034BF0D00BDE1A681206D51C0E8E21A80081520C00000000000000840
343	\N	\N	\N	\N	01010000A034BF0D006D1D9B4B54EF51C0D088E7334CAF1DC00000000000000840
344	\N	\N	\N	\N	01010000A034BF0D001D1F5481CC0352C0E06D57D8C8671CC00000000000000840
345	\N	\N	\N	\N	01010000A034BF0D00A18F30A7BFDD51C0B02AC32D53D816C00000000000000840
346	\N	\N	\N	\N	01010000A034BF0D006D6DBFB4A2C051C0B02AC32D53D816C00000000000000840
347	\N	\N	\N	\N	01010000A034BF0D00398590816F7D51C0B02AC32D53D816C00000000000000840
348	\N	\N	\N	\N	01010000A034BF0D00398590816F7D51C0D06BAE083BFC12C00000000000000840
349	\N	\N	\N	\N	01010000A034BF0D00118590816F7D51C0A0119B78979B0EC00000000000000840
350	\N	\N	\N	\N	01010000A034BF0D00398590816F7D51C080F870FE635813C00000000000000840
351	\N	\N	\N	\N	01010000A034BF0D00D33D983A013851C0D06BAE083BFC12C00000000000000840
352	\N	\N	\N	\N	01010000A034BF0D005F33C196903A51C0E03EA86C0E910EC00000000000000840
353	\N	\N	\N	\N	01010000A034BF0D00D33D983A013851C080F870FE635813C00000000000000840
354	\N	\N	\N	\N	01010000A034BF0D006D6DBFB4A2C051C0D06BAE083BFC12C00000000000000840
355	\N	\N	\N	\N	01010000A034BF0D004F6DBFB4A2C051C060119B78979B0EC00000000000000840
356	\N	\N	\N	\N	01010000A034BF0D006D6DBFB4A2C051C080F870FE635813C00000000000000840
357	\N	\N	\N	\N	01010000A034BF0D00D34E483C5E0552C080F870FE635813C00000000000000840
358	\N	\N	\N	\N	01010000A034BF0D001D5111D6630652C0E0D3E0610A4813C00000000000000840
359	\N	\N	\N	\N	01010000A034BF0D006753DA6F690752C080F870FE635813C00000000000000840
360	\N	\N	\N	\N	01010000A034BF0D00898BBC2C391652C0904A640F871D14C00000000000000840
361	\N	\N	\N	\N	01010000A034BF0D001D5111D6630652C02069AE083BFC12C00000000000000840
362	\N	\N	\N	\N	01010000A034BF0D00475BE879D40352C060AB1840CD9B0EC00000000000000840
363	\N	\N	\N	\N	01010000A034BF0D0099AA3DB0479850C0F070D3CB92EB20C00000000000000840
364	\N	\N	\N	\N	01010000A034BF0D00AEC273CF07EC4FC0E849C9C798C22CC00000000000000840
365	\N	\N	\N	\N	01010000A034BF0D0092957199842F4FC0407371D3FE5830C00000000000000840
366	\N	\N	\N	\N	01010000A034BF0D00AEC273CF07EC4FC0A882E09D5E5C2CC00000000000000840
367	\N	\N	\N	\N	01010000A034BF0D0046EE2307832F4FC0B8F184A14B5A31C00000000000000840
368	\N	\N	\N	\N	01010000A034BF0D0002377E00BD514EC0747176ECFA1133C00000000000000840
369	\N	\N	\N	\N	01010000A034BF0D0066B76A90ED344FC03C09A0E36BF832C00000000000000840
370	\N	\N	\N	\N	01010000A034BF0D004A4575C6C2EA4EC0487D2B3347F32FC00000000000000840
371	\N	\N	\N	\N	01010000A034BF0D003AF6335C46984DC01084700FA3F820C00000000000000840
372	\N	\N	\N	\N	01010000A034BF0D00A2A11379631F4EC01084700FA3F820C00000000000000840
373	\N	\N	\N	\N	01010000A034BF0D000A196671F6C14EC0C035E923800A20C00000000000000840
374	\N	\N	\N	\N	01010000A034BF0D0082D7AE70F4FF4DC01084700FA3F820C00000000000000840
375	\N	\N	\N	\N	01010000A034BF0D003ADBB40582894FC0C035E923800A20C00000000000000840
376	\N	\N	\N	\N	01010000A034BF0D007E87972A08874EC090AF1EB1B49E1DC00000000000000840
377	\N	\N	\N	\N	01010000A034BF0D003637CF3EBAA54EC050D23B5DDCBD16C00000000000000840
378	\N	\N	\N	\N	01010000A034BF0D00C2F75E5DC0E54EC050D23B5DDCBD16C00000000000000840
379	\N	\N	\N	\N	01010000A034BF0D0032C8BCC3266C4FC050D23B5DDCBD16C00000000000000840
380	\N	\N	\N	\N	01010000A034BF0D00A681797AB7F54FC040599F9BB6E112C00000000000000840
381	\N	\N	\N	\N	01010000A034BF0D001A9627C298F04FC0808FD5649B470EC00000000000000840
382	\N	\N	\N	\N	01010000A034BF0D00A281797AB7F54FC030EA6191DF3D13C00000000000000840
383	\N	\N	\N	\N	01010000A034BF0D0046C8BCC3266C4FC040599F9BB6E112C00000000000000840
384	\N	\N	\N	\N	01010000A034BF0D005EC8BCC3266C4FC040B905E4E1660EC00000000000000840
385	\N	\N	\N	\N	01010000A034BF0D0042C8BCC3266C4FC030EA6191DF3D13C00000000000000840
386	\N	\N	\N	\N	01010000A034BF0D00D6F75E5DC0E54EC040599F9BB6E112C00000000000000840
387	\N	\N	\N	\N	01010000A034BF0D00E6F75E5DC0E54EC0C0B805E4E1660EC00000000000000840
388	\N	\N	\N	\N	01010000A034BF0D00D2F75E5DC0E54EC030EA6191DF3D13C00000000000000840
389	\N	\N	\N	\N	01010000A034BF0D00FAF10F4A34644EC040599F9BB6E112C00000000000000840
390	\N	\N	\N	\N	01010000A034BF0D0026C4F309175E4EC0C0EDDBB4107B0EC00000000000000840
391	\N	\N	\N	\N	01010000A034BF0D00FAF10F4A34644EC030EA6191DF3D13C00000000000000840
392	\N	\N	\N	\N	01010000A034BF0D00662FF341625F4EC0D0EEFB6B85611CC00000000000000840
393	\N	\N	\N	\N	01010000A034BF0D003AF6335C46984DC0401FBFA2D79E1FC00000000000000840
394	\N	\N	\N	\N	01010000A034BF0D00F6B180612A134CC068A7AD1237D725C00000000000000840
395	\N	\N	\N	\N	01010000A034BF0D0076BF72FA34EA4AC068A7AD1237D725C00000000000000840
396	\N	\N	\N	\N	01010000A034BF0D002230B0040C4E4AC0E0138A0BBFF526C00000000000000840
397	\N	\N	\N	\N	01010000A034BF0D006AA776C5A31E4AC0C836700860B327C00000000000000840
398	\N	\N	\N	\N	01010000A034BF0D00FA74D8DA927948C0C836700860B327C00000000000000840
399	\N	\N	\N	\N	01010000A034BF0D008277BC0637E547C0C836700860B327C00000000000000840
400	\N	\N	\N	\N	01010000A034BF0D00D21849189D5047C0C836700860B327C00000000000000840
401	\N	\N	\N	\N	01010000A034BF0D00D21849189D5047C0A8FCC28A664523C00000000000000840
402	\N	\N	\N	\N	01010000A034BF0D001AFAC32C4B9847C090237F4BD4C617C00000000000000840
403	\N	\N	\N	\N	01010000A034BF0D00D21849189D5047C0A03A7185218023C00000000000000840
404	\N	\N	\N	\N	01010000A034BF0D00EADD226D9D4B47C0C836700860B327C00000000000000840
405	\N	\N	\N	\N	01010000A034BF0D0046C63E9D2FDE46C0C836700860B327C00000000000000840
406	\N	\N	\N	\N	01010000A034BF0D00387FAF7E03B746C0901A338EAF1627C00000000000000840
407	\N	\N	\N	\N	01010000A034BF0D00387FAF7E03B746C058FCC28A664523C00000000000000840
408	\N	\N	\N	\N	01010000A034BF0D00685F59C0606E46C07018599A79CE17C00000000000000840
409	\N	\N	\N	\N	01010000A034BF0D00387FAF7E03B746C0A03A7185218023C00000000000000840
410	\N	\N	\N	\N	01010000A034BF0D00085C4E6B9D4B45C058D009A2F9CC25C00000000000000840
411	\N	\N	\N	\N	01010000A034BF0D00085C4E6B9D4B45C058FCC28A664523C00000000000000840
412	\N	\N	\N	\N	01010000A034BF0D008E522D8DDA6A45C0B0E176D36AB215C00000000000000840
413	\N	\N	\N	\N	01010000A034BF0D00085C4E6B9D4B45C0A03A7185218023C00000000000000840
414	\N	\N	\N	\N	01010000A034BF0D00A2F5E704372543C058D009A2F9CC25C00000000000000840
415	\N	\N	\N	\N	01010000A034BF0D00A2F5E704372543C058FCC28A664523C00000000000000840
416	\N	\N	\N	\N	01010000A034BF0D000C525BF8121F43C0A036C52A09261AC00000000000000840
417	\N	\N	\N	\N	01010000A034BF0D00A2F5E704372543C0A03A7185218023C00000000000000840
418	\N	\N	\N	\N	01010000A034BF0D002673E369714B41C058D009A2F9CC25C00000000000000840
419	\N	\N	\N	\N	01010000A034BF0D002673E369714B41C058FCC28A664523C00000000000000840
420	\N	\N	\N	\N	01010000A034BF0D0070060287BF4441C07081695DA1201AC00000000000000840
421	\N	\N	\N	\N	01010000A034BF0D002673E369714B41C0A03A7185218023C00000000000000840
422	\N	\N	\N	\N	01010000A034BF0D00A28CEF4DD9CA40C058D009A2F9CC25C00000000000000840
423	\N	\N	\N	\N	01010000A034BF0D00E47F606D7C303EC058D009A2F9CC25C00000000000000840
424	\N	\N	\N	\N	01010000A034BF0D00E47F606D7C303EC058FCC28A664523C00000000000000840
425	\N	\N	\N	\N	01010000A034BF0D000AC1ECAFF11740C0C010C4DDC78B15C00000000000000840
426	\N	\N	\N	\N	01010000A034BF0D00E47F606D7C303EC0A03A7185218023C00000000000000840
427	\N	\N	\N	\N	01010000A034BF0D00F45BF6C287593BC0A89F80F1911227C00000000000000840
428	\N	\N	\N	\N	01010000A034BF0D00AC71F9CBCE103BC038747ADF03A427C00000000000000840
429	\N	\N	\N	\N	01010000A034BF0D00309F81187B303AC038747ADF03A427C00000000000000840
430	\N	\N	\N	\N	01010000A034BF0D00C428C38F54263AC038747ADF03A427C00000000000000840
431	\N	\N	\N	\N	01010000A034BF0D00C428C38F54263AC088FDC28A664523C00000000000000840
432	\N	\N	\N	\N	01010000A034BF0D00C066CD66F89639C030BED003F3CB17C00000000000000840
433	\N	\N	\N	\N	01010000A034BF0D00C428C38F54263AC0A03A7185218023C00000000000000840
434	\N	\N	\N	\N	01010000A034BF0D00FC6B4EE547FD38C038747ADF03A427C00000000000000840
435	\N	\N	\N	\N	01010000A034BF0D007070A40A69D437C038747ADF03A427C00000000000000840
436	\N	\N	\N	\N	01010000A034BF0D007070A40A69D437C058FCC28A664523C00000000000000840
437	\N	\N	\N	\N	01010000A034BF0D003C1A9971234337C0700827C498D317C00000000000000840
438	\N	\N	\N	\N	01010000A034BF0D007070A40A69D437C0A03A7185218023C00000000000000840
439	\N	\N	\N	\N	01010000A034BF0D001478CFF27D8134C038747ADF03A427C00000000000000840
440	\N	\N	\N	\N	01010000A034BF0D00645D6EE8582634C0D83EB8CAB9ED26C00000000000000840
441	\N	\N	\N	\N	01010000A034BF0D00645D6EE8582634C058FCC28A664523C00000000000000840
442	\N	\N	\N	\N	01010000A034BF0D00AC62367FA0B734C0E030C80282CE17C00000000000000840
443	\N	\N	\N	\N	01010000A034BF0D00645D6EE8582634C0A03A7185218023C00000000000000840
444	\N	\N	\N	\N	01010000A034BF0D00302A3BB525F332C058D009A2F9CC25C00000000000000840
445	\N	\N	\N	\N	01010000A034BF0D0024B4F1A7B3A030C058D009A2F9CC25C00000000000000840
446	\N	\N	\N	\N	01010000A034BF0D0070E5CB16888E29C0A0C8AB774CA125C00000000000000840
447	\N	\N	\N	\N	01010000A034BF0D00F8788019788324C0D8EDB5F420A327C00000000000000840
448	\N	\N	\N	\N	01010000A034BF0D00005EA33F689E22C0D8EDB5F420A327C00000000000000840
449	\N	\N	\N	\N	01010000A034BF0D0060347A8B256C17C0F0C85F011B9E27C00000000000000840
450	\N	\N	\N	\N	01010000A034BF0D0070B4213EB5C014C0F0C85F011B9E27C00000000000000840
451	\N	\N	\N	\N	01010000A034BF0D0080DCB2204E8804C0F0C85F011B9E27C00000000000000840
452	\N	\N	\N	\N	01010000A034BF0D00004C1A109A22E93F28897F828FFD20C00000000000000840
453	\N	\N	\N	\N	01010000A034BF0D000010C12DEE49CFBF28897F828FFD20C00000000000000840
454	\N	\N	\N	\N	01010000A034BF0D0040BDD35CC1B5F7BFE8968166ED1A20C00000000000000840
455	\N	\N	\N	\N	01010000A034BF0D000000DE473AC2763F28897F828FFD20C00000000000000840
456	\N	\N	\N	\N	01010000A034BF0D0080235D8414FB08C0E8968166ED1A20C00000000000000840
457	\N	\N	\N	\N	01010000A034BF0D0080F5B51E2CD5F0BFE088E89125971DC00000000000000840
458	\N	\N	\N	\N	01010000A034BF0D0000172739EF64F5BF4034A69E5BEE16C00000000000000840
459	\N	\N	\N	\N	01010000A034BF0D00C08C2C52A73CFCBF4034A69E5BEE16C00000000000000840
460	\N	\N	\N	\N	01010000A034BF0D00004DF30EBA8406C04034A69E5BEE16C00000000000000840
461	\N	\N	\N	\N	01010000A034BF0D008060E6C8A14C0FC0208876BC630013C00000000000000840
462	\N	\N	\N	\N	01010000A034BF0D0040A9C743B6FA0EC080A98C83D4800EC00000000000000840
463	\N	\N	\N	\N	01010000A034BF0D008060E6C8A14C0FC0301739B28C5C13C00000000000000840
464	\N	\N	\N	\N	01010000A034BF0D00004DF30EBA8406C0208876BC630013C00000000000000840
465	\N	\N	\N	\N	01010000A034BF0D00804EF30EBA8406C0C05495B43E710EC00000000000000840
466	\N	\N	\N	\N	01010000A034BF0D00004DF30EBA8406C0301739B28C5C13C00000000000000840
467	\N	\N	\N	\N	01010000A034BF0D00C08C2C52A73CFCBF208876BC630013C00000000000000840
468	\N	\N	\N	\N	01010000A034BF0D00008E2C52A73CFCBFC05495B43E710EC00000000000000840
469	\N	\N	\N	\N	01010000A034BF0D00C08C2C52A73CFCBF301739B28C5C13C00000000000000840
470	\N	\N	\N	\N	01010000A034BF0D0000B15DBEEEBAE8BF301739B28C5C13C00000000000000840
471	\N	\N	\N	\N	01010000A034BF0D000092B9B7F7D5E7BF80CB21856B3C13C00000000000000840
472	\N	\N	\N	\N	01010000A034BF0D000092B9B7F7D5E7BF208876BC630013C00000000000000840
473	\N	\N	\N	\N	01010000A034BF0D00007834CCA51DE7BF0078C184C2610EC00000000000000840
474	\N	\N	\N	\N	01010000A034BF0D008034FF4EEED4E6BF301739B28C5C13C00000000000000840
475	\N	\N	\N	\N	01010000A034BF0D00002DA4B8CFD2DBBFB0D5E8FACB1914C00000000000000840
476	\N	\N	\N	\N	01010000A034BF0D008003FADFAE0FE6BFF04B3A66D0231CC00000000000000840
477	\N	\N	\N	\N	01010000A034BF0D00004C1A109A22E93F8095376C5B421FC00000000000000840
478	\N	\N	\N	\N	01010000A034BF0D004069437C6A810CC060D06649BBDE2CC00000000000000840
479	\N	\N	\N	\N	01010000A034BF0D00207863FE4CE802C0BCCCD5BAE76830C00000000000000840
480	\N	\N	\N	\N	01010000A034BF0D004069437C6A810CC0C8BA8D5CEB5A2CC00000000000000840
481	\N	\N	\N	\N	01010000A034BF0D00207863FE4CE802C0C4FD4CF775E630C00000000000000840
482	\N	\N	\N	\N	01010000A034BF0D00802FA1F870ABE8BF747473F0CD5C32C00000000000000840
483	\N	\N	\N	\N	01010000A034BF0D0040C6E66CB0FC02C0FC189D930EA931C00000000000000840
484	\N	\N	\N	\N	01010000A034BF0D0040C6E66CB0FC02C0C4E2A3B0264E35C00000000000000840
485	\N	\N	\N	\N	01010000A034BF0D0000CA6284DCA501C0EC9F3233925235C00000000000000840
486	\N	\N	\N	\N	01010000A034BF0D00E0BDD788106302C0AC98E401388535C00000000000000840
487	\N	\N	\N	\N	01010000A034BF0D006050BBD74E5A12C0FC189D930EA931C00000000000000840
488	\N	\N	\N	\N	01010000A034BF0D00400781AB8F8B19C0FC189D930EA931C00000000000000840
489	\N	\N	\N	\N	01010000A034BF0D00404EBBD74E5A11C0FC189D930EA931C00000000000000840
490	\N	\N	\N	\N	01010000A034BF0D00400781AB8F8B19C0EC12A61DAB9433C00000000000000840
491	\N	\N	\N	\N	01010000A034BF0D00F05DA33F68DE20C0A4D0749DE5AC35C00000000000000840
492	\N	\N	\N	\N	01010000A034BF0D00308A991BCBF222C0A483A722F33E36C00000000000000840
493	\N	\N	\N	\N	01010000A034BF0D00105FA33F685E20C0A4D0749DE5AC35C00000000000000840
494	\N	\N	\N	\N	01010000A034BF0D00F8CABD00F0FD26C0244846A9593E36C00000000000000840
495	\N	\N	\N	\N	01010000A034BF0D0078B7711D6F3B21C0FC6CBB21A11A37C00000000000000840
496	\N	\N	\N	\N	01010000A034BF0D00F05DA33F68DE20C0EC12A61DAB9433C00000000000000840
497	\N	\N	\N	\N	01010000A034BF0D00D84014EA1F7127C054B90F6DE02934C00000000000000840
498	\N	\N	\N	\N	01010000A034BF0D00105FA33F685E20C0EC12A61DAB9433C00000000000000840
499	\N	\N	\N	\N	01010000A034BF0D0070B4213EB5C014C0B00C467B70462CC00000000000000840
500	\N	\N	\N	\N	01010000A034BF0D0070B4213EB5C014C0409C1657F7752CC00000000000000840
501	\N	\N	\N	\N	01010000A034BF0D00004CEF09953DE9BFFC302EA7991931C00000000000000840
502	\N	\N	\N	\N	01010000A034BF0D00301A9ED3BD9619C0407B8399F92BFEBF0000000000000840
503	\N	\N	\N	\N	01010000A034BF0D00301A9ED3BD9619C0C0DB85ACAD86FDBF0000000000000840
504	\N	\N	\N	\N	01010000A034BF0D00301A9ED3BD9619C0C0F21BF96249FCBF0000000000000840
505	\N	\N	\N	\N	01010000A034BF0D006079F527AB7011C0C0DB85ACAD86FDBF0000000000000840
506	\N	\N	\N	\N	01010000A034BF0D0000C3E64694CDF4BF80D1E64694CDF4BF0000000000000840
507	\N	\N	\N	\N	01010000A034BF0D008078F527AB7012C0C0DB85ACAD86FDBF0000000000000840
508	\N	\N	\N	\N	01010000A034BF0D00F05DA33F68DE20C0407B8399F92BFEBF0000000000000840
509	\N	\N	\N	\N	01010000A034BF0D001079B440D10C27C080F0E816D5DAF3BF0000000000000840
510	\N	\N	\N	\N	01010000A034BF0D00F05DA33F685E20C0407B8399F92BFEBF0000000000000840
511	\N	\N	\N	\N	01010000A034BF0D0050A4B0C2940825C0909B9E7061F128C00000000000000840
512	\N	\N	\N	\N	01010000A034BF0D00F00461169C2D2BC010E0328373FB20C00000000000000840
513	\N	\N	\N	\N	01010000A034BF0D00F00461169C2D2BC080856023A4371FC00000000000000840
514	\N	\N	\N	\N	01010000A034BF0D001865BD4E9F1129C010E0328373FB20C00000000000000840
515	\N	\N	\N	\N	01010000A034BF0D00D84F6758E4EA26C0500EA35738771FC00000000000000840
516	\N	\N	\N	\N	01010000A034BF0D003091D6729B9129C010E0328373FB20C00000000000000840
517	\N	\N	\N	\N	01010000A034BF0D00A85F773F685E23C0F8316F5BDB1420C00000000000000840
518	\N	\N	\N	\N	01010000A034BF0D00C81ADF741A7827C060D6707B0C011DC00000000000000840
519	\N	\N	\N	\N	01010000A034BF0D001084D38C95E328C040325D3A1A2A1AC00000000000000840
520	\N	\N	\N	\N	01010000A034BF0D0028A17C8670EB26C0B078FB1B55E716C00000000000000840
521	\N	\N	\N	\N	01010000A034BF0D0088AE9C064B0F26C0B078FB1B55E716C00000000000000840
522	\N	\N	\N	\N	01010000A034BF0D00E06C256DB1F523C0B078FB1B55E716C00000000000000840
523	\N	\N	\N	\N	01010000A034BF0D00E06C256DB1F523C0F0F826E7590B13C00000000000000840
524	\N	\N	\N	\N	01010000A034BF0D00C06C256DB1F523C0606A3F6271870EC00000000000000840
525	\N	\N	\N	\N	01010000A034BF0D00E06C256DB1F523C0A086E9DC826713C00000000000000840
526	\N	\N	\N	\N	01010000A034BF0D0088E0DC5CA2C321C0F0F826E7590B13C00000000000000840
527	\N	\N	\N	\N	01010000A034BF0D006090243E1DD821C02099CA851A970EC00000000000000840
528	\N	\N	\N	\N	01010000A034BF0D0088E0DC5CA2C321C0A086E9DC826713C00000000000000840
529	\N	\N	\N	\N	01010000A034BF0D0088AE9C064B0F26C0F0F826E7590B13C00000000000000840
530	\N	\N	\N	\N	01010000A034BF0D00A0AE9C064B0F26C0A026A42F30870EC00000000000000840
531	\N	\N	\N	\N	01010000A034BF0D0088AE9C064B0F26C0A086E9DC826713C00000000000000840
532	\N	\N	\N	\N	01010000A034BF0D00307CAFA8562828C050F726E7590B13C00000000000000840
533	\N	\N	\N	\N	01010000A034BF0D0078DEA186893028C0C032422BF4FA12C00000000000000840
534	\N	\N	\N	\N	01010000A034BF0D00280AB6A6490728C0A086E9DC826713C00000000000000840
535	\N	\N	\N	\N	01010000A034BF0D00700AB2397E0228C0A0D1B7C8D7ED0DC00000000000000840
536	\N	\N	\N	\N	01010000A034BF0D00688875DFD06628C0A086E9DC826713C00000000000000840
537	\N	\N	\N	\N	01010000A034BF0D00688C0E9784C628C0104151638BFE13C00000000000000840
538	\N	\N	\N	\N	01010000A034BF0D00C0409464BC3828C050F726E7590B13C00000000000000840
539	\N	\N	\N	\N	01010000A034BF0D0024B4F1A7B3A030C058FCC28A664523C00000000000000840
540	\N	\N	\N	\N	01010000A034BF0D008C8EDE26AF0F30C0B048466494D217C00000000000000840
541	\N	\N	\N	\N	01010000A034BF0D0024B4F1A7B3A030C0A03A7185218023C00000000000000840
542	\N	\N	\N	\N	01010000A034BF0D00302A3BB525F332C058FCC28A664523C00000000000000840
543	\N	\N	\N	\N	01010000A034BF0D0098083048866332C06036261400CD17C00000000000000840
544	\N	\N	\N	\N	01010000A034BF0D00302A3BB525F332C0A03A7185218023C00000000000000840
545	\N	\N	\N	\N	01010000A034BF0D00885684B57FF232C0B06683A6FB8B15C00000000000000840
546	\N	\N	\N	\N	01010000A034BF0D00D0CE647C4E4F32C0404FF9E4207C17C00000000000000840
547	\N	\N	\N	\N	01010000A034BF0D00F458A3AC7DFC32C0682CAE2E56B52AC00000000000000840
548	\N	\N	\N	\N	01010000A034BF0D00686D51F45E5732C0682CAE2E56B52AC00000000000000840
549	\N	\N	\N	\N	01010000A034BF0D00C4AFACCE5FCA30C01837BA6F7D6B2BC00000000000000840
550	\N	\N	\N	\N	01010000A034BF0D0048DBCAC58C6F32C0682CAE2E56B52AC00000000000000840
551	\N	\N	\N	\N	01010000A034BF0D0000A8FA86D2A330C0C4DA1D681E2731C00000000000000840
552	\N	\N	\N	\N	01010000A034BF0D002014D20977792FC06082F448E5172AC00000000000000840
553	\N	\N	\N	\N	01010000A034BF0D00F458A3AC7DFC32C0608DBFFA29042CC00000000000000840
554	\N	\N	\N	\N	01010000A034BF0D0088D2DABDB12234C0E4DE5B49622631C00000000000000840
555	\N	\N	\N	\N	01010000A034BF0D00F458A3AC7DFC32C0C8AD8339E6C72BC00000000000000840
556	\N	\N	\N	\N	01010000A034BF0D00FC6B4EE547FD38C0608DBFFA29042CC00000000000000840
557	\N	\N	\N	\N	01010000A034BF0D00180A78BB91D737C0B0C2E58C6F2931C00000000000000840
558	\N	\N	\N	\N	01010000A034BF0D00FC6B4EE547FD38C0C8AD8339E6C72BC00000000000000840
559	\N	\N	\N	\N	01010000A034BF0D00309F81187B303AC0608DBFFA29042CC00000000000000840
560	\N	\N	\N	\N	01010000A034BF0D000C429E7125563BC07C819F5D7B2931C00000000000000840
561	\N	\N	\N	\N	01010000A034BF0D00309F81187B303AC0C8AD8339E6C72BC00000000000000840
562	\N	\N	\N	\N	01010000A034BF0D004856D4771B3C3DC0D842A7C82A9F2AC00000000000000840
563	\N	\N	\N	\N	01010000A034BF0D00DC7961E1080A3FC0CCEBA462E22931C00000000000000840
564	\N	\N	\N	\N	01010000A034BF0D00780EFEF8BF223DC0D842A7C82A9F2AC00000000000000840
565	\N	\N	\N	\N	01010000A034BF0D00F45BF6C287593BC058FCC28A664523C00000000000000840
566	\N	\N	\N	\N	01010000A034BF0D0094A7D685D1EA3BC090E27A6BA9D317C00000000000000840
567	\N	\N	\N	\N	01010000A034BF0D00F45BF6C287593BC0A03A7185218023C00000000000000840
568	\N	\N	\N	\N	01010000A034BF0D00A28CEF4DD9CA40C0D0BB70247F5128C00000000000000840
569	\N	\N	\N	\N	01010000A034BF0D00720A1B4CD93A41C078A947790E942BC00000000000000840
570	\N	\N	\N	\N	01010000A034BF0D00A28CEF4DD9CA40C01866A2BED11928C00000000000000840
571	\N	\N	\N	\N	01010000A034BF0D00E8F91B995E4441C0D81530EDE72831C00000000000000840
572	\N	\N	\N	\N	01010000A034BF0D00A46DE562C63742C02893DB4C143F2AC00000000000000840
573	\N	\N	\N	\N	01010000A034BF0D00DA795919FE1E43C0D0F470F0612A31C00000000000000840
574	\N	\N	\N	\N	01010000A034BF0D00B81B2D44412C42C02893DB4C143F2AC00000000000000840
575	\N	\N	\N	\N	01010000A034BF0D0050B5C6DDDAC545C01097699D8F9B2AC00000000000000840
576	\N	\N	\N	\N	01010000A034BF0D002AE29E425CDE44C0B082D8B9EF2A31C00000000000000840
577	\N	\N	\N	\N	01010000A034BF0D003C077FFC5FD145C01097699D8F9B2AC00000000000000840
578	\N	\N	\N	\N	01010000A034BF0D00EADD226D9D4B47C0C8AB17E570162CC00000000000000840
579	\N	\N	\N	\N	01010000A034BF0D0032B942B399B846C0544010F1652A31C00000000000000840
580	\N	\N	\N	\N	01010000A034BF0D00EADD226D9D4B47C0E8326F8B9EE62BC00000000000000840
581	\N	\N	\N	\N	01010000A034BF0D008277BC0637E547C0C8AB17E570162CC00000000000000840
582	\N	\N	\N	\N	01010000A034BF0D00B60B1BDCF57748C0CC6213BAEF2A31C00000000000000840
583	\N	\N	\N	\N	01010000A034BF0D008277BC0637E547C0E8326F8B9EE62BC00000000000000840
584	\N	\N	\N	\N	01010000A034BF0D00FA74D8DA927948C058FCC28A664523C00000000000000840
585	\N	\N	\N	\N	01010000A034BF0D00FE5F79CA37C248C01072AF248BCE17C00000000000000840
586	\N	\N	\N	\N	01010000A034BF0D00FA74D8DA927948C0A03A7185218023C00000000000000840
587	\N	\N	\N	\N	01010000A034BF0D002A89E0F291DC4AC0D0BD17BE18AB2AC00000000000000840
588	\N	\N	\N	\N	01010000A034BF0D001A4A73B5BFE44AC0C8AB17E570162CC00000000000000840
589	\N	\N	\N	\N	01010000A034BF0D00BEA46EA426E54AC0A0871164DBF22CC00000000000000840
590	\N	\N	\N	\N	01010000A034BF0D001A4A73B5BFE44AC0E8326F8B9EE62BC00000000000000840
591	\N	\N	\N	\N	01010000A034BF0D00C2E2BE4C33524AC03460D5F0652A31C00000000000000840
592	\N	\N	\N	\N	01010000A034BF0D00BA3B6FDAEBE64AC0B8C17D9E49EC2CC00000000000000840
593	\N	\N	\N	\N	01010000A034BF0D00A26DE562C6374BC0D0BD17BE18AB2AC00000000000000840
594	\N	\N	\N	\N	01010000A034BF0D00762D136861FE4BC0C84562183B792BC00000000000000840
595	\N	\N	\N	\N	01010000A034BF0D0072663666732B4BC0D0BD17BE18AB2AC00000000000000840
596	\N	\N	\N	\N	01010000A034BF0D005AFB95758F114CC0B4B650BAEF2A31C00000000000000840
597	\N	\N	\N	\N	01010000A034BF0D00AA55D6EE867B4CC0F05578E257212AC00000000000000840
598	\N	\N	\N	\N	01010000A034BF0D002230B0040C4E4AC058FCC28A664523C00000000000000840
599	\N	\N	\N	\N	01010000A034BF0D009A8F1D7EF9074AC0303E9B6BBAAF17C00000000000000840
600	\N	\N	\N	\N	01010000A034BF0D002230B0040C4E4AC0A03A7185218023C00000000000000840
601	\N	\N	\N	\N	01010000A034BF0D0076BF72FA34EA4AC030FCC28A664523C00000000000000840
602	\N	\N	\N	\N	01010000A034BF0D001EEC2CE1E2314BC020EE8F8B1AA817C00000000000000840
603	\N	\N	\N	\N	01010000A034BF0D0076BF72FA34EA4AC0A03A7185218023C00000000000000840
604	\N	\N	\N	\N	01010000A034BF0D00F6B180612A134CC058FCC28A664523C00000000000000840
605	\N	\N	\N	\N	01010000A034BF0D0082157E5AD05B4CC030A5A91DDBAF17C00000000000000840
606	\N	\N	\N	\N	01010000A034BF0D00F6B180612A134CC0A03A7185218023C00000000000000840
607	\N	\N	\N	\N	01010000A034BF0D00729D11BACC3A4DC0087A062202F128C00000000000000840
608	\N	\N	\N	\N	01010000A034BF0D008E0842B888974DC078166ED7EE912FC00000000000000840
609	\N	\N	\N	\N	01010000A034BF0D000A67A82029584DC0B0DD0EA2B14730C00000000000000840
610	\N	\N	\N	\N	01010000A034BF0D0022E5763D5CDB4DC0FC31A1C8A35030C00000000000000840
611	\N	\N	\N	\N	01010000A034BF0D00005EA33F689E22C0108FFE4D940F2DC00000000000000840
612	\N	\N	\N	\N	01010000A034BF0D00F87D8A907CF124C05807A30C40F631C00000000000000840
613	\N	\N	\N	\N	01010000A034BF0D003B548F320E5451C088FDF44BA63D2DC00000000000000840
614	\N	\N	\N	\N	01010000A034BF0D0089855B35799E51C044E93BEB08DE31C00000000000000840
\.


--
-- Data for Name: first_floor_rooms; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.first_floor_rooms (level, _area_id, _coordsys, geom) FROM stdin;
first_floor	1mWTVVwiXDHQKYjSZ048h5	IFC_COORDSYS_0	01030000A034BF0D000100000039000000008CEEB16C06C4BFF02F5D4DB8CA28C0E11FD26F5F07DEBF003E4281DCFDF43F487E89C66BC228C0E11FD26F5F07DEBF003E4281DCFDF43F387CEC74B3F522C0E11FD26F5F07DEBF006ED2D5D70BF93F387CEC74B3F522C0E11FD26F5F07DEBF006ED2D5D70BF93FE0D47EF7372A1CC0E11FD26F5F07DEBF0000A10A9780793FE0D47EF7372A1CC0E11FD26F5F07DEBF0000A10A9780793F706ABFFB1B1523C0E11FD26F5F07DEBF8078F527AB7012C0706ABFFB1B1523C0E11FD26F5F07DEBF8078F527AB7012C00000000000000000E11FD26F5F07DEBF70EF2DC7886B20C00000000000000000E11FD26F5F07DEBF70EF2DC7886B20C0D8CD37AF040023C0E11FD26F5F07DEBF7045B886699629C0D8CD37AF040023C0E11FD26F5F07DEBF7045B886699629C0E0D47EF7372A1CC0E11FD26F5F07DEBFB078EBB99CC92CC0E0D47EF7372A1CC0E11FD26F5F07DEBFB078EBB99CC92CC068A2B74D2AE822C0E11FD26F5F07DEBF30BA4A85C7282CC068A2B74D2AE822C0E11FD26F5F07DEBF30BA4A85C7282CC0003C51E7C38123C0E11FD26F5F07DEBF5A7B1FAEFE564DC0D03951E7C38123C0E11FD26F5F07DEBF5A7B1FAEFE564DC010C2720549FE22C0E11FD26F5F07DEBFF214B94798304DC010C2720549FE22C0E11FD26F5F07DEBFF214B94798304DC090EA4B71F8621CC0E11FD26F5F07DEBF7A382FBFE7FD4DC090EA4B71F8621CC0E11FD26F5F07DEBF7A382FBFE7FD4DC010C2720549FE22C0E11FD26F5F07DEBF51A9037F0A2650C010C2720549FE22C0E11FD26F5F07DEBF51A9037F0A2650C0F050B2D75EC91AC0E11FD26F5F07DEBFB90F6AE5700C51C0F050B2D75EC91AC0E11FD26F5F07DEBFB90F6AE5700C51C018AA5A87180223C0E11FD26F5F07DEBF71CFCA12273252C018AA5A87180223C0E11FD26F5F07DEBF71CFCA12273252C0B05F05658B5D1CC0E11FD26F5F07DEBF71CFCA12279252C0B05F05658B5D1CC0E11FD26F5F07DEBF71CFCA12279252C0A07C4F7F92FB22C0E11FD26F5F07DEBF6148BE185A8752C0A07C4F7F92FB22C0E11FD26F5F07DEBF6148BE185A8752C070491C4C5FC828C0E11FD26F5F07DEBF15AF5FB3E79052C070491C4C5FC828C0E11FD26F5F07DEBF15AF5FB3E79052C0EC5741D9629730C0E11FD26F5F07DEBF05D1E2877A3252C0EC5741D9629730C0E11FD26F5F07DEBF05D1E2877A3252C0C8269DCAD13D2CC0E11FD26F5F07DEBFD154EE9D272352C0C8269DCAD13D2CC0E11FD26F5F07DEBFD154EE9D272352C0308D033138A42DC0E11FD26F5F07DEBF390F9FE1D41D51C0308D033138A42DC0E11FD26F5F07DEBF390F9FE1D41D51C0C8269DCAD13D2CC0E11FD26F5F07DEBF311A35AC787250C0C8269DCAD13D2CC0E11FD26F5F07DEBF311A35AC787250C0B4013175957A32C0E11FD26F5F07DEBF3DC11584372650C0B4013175957A32C0E11FD26F5F07DEBF3DC11584372650C09836951D5E282CC0E11FD26F5F07DEBF7A822B086F0C4EC09836951D5E282CC0E11FD26F5F07DEBF7A822B086F0C4EC0009DFB83C48E28C0E11FD26F5F07DEBF4A4FF8D43B594DC0009DFB83C48E28C0E11FD26F5F07DEBF4A4FF8D43B594DC0289D3316882B28C0E11FD26F5F07DEBFF009AE20BC3129C0289D3316882B28C0E11FD26F5F07DEBFF009AE20BC3129C090039A7CEE912DC0E11FD26F5F07DEBF00A177FB2EEA20C090039A7CEE912DC0E11FD26F5F07DEBF00A177FB2EEA20C060D06649BB5E2CC0E11FD26F5F07DEBF0098C555DD43CEBF60D06649BB5E2CC0E11FD26F5F07DEBF0098C555DD43CEBF701BAF05D74F2CC0E11FD26F5F07DEBF008CEEB16C06C4BF701BAF05D74F2CC0E11FD26F5F07DEBF008CEEB16C06C4BFF02F5D4DB8CA28C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048ky	IFC_COORDSYS_0	01030000A034BF0D000100000005000000105FA33F685E20C0409C1657F7752CC0E11FD26F5F07DEBF105FA33F685E20C0A881F5AD091B37C0E11FD26F5F07DEBF6050BBD74E5A12C0A881F5AD091B37C0E11FD26F5F07DEBF6050BBD74E5A12C0409C1657F7752CC0E11FD26F5F07DEBF105FA33F685E20C0409C1657F7752CC0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6Oe	IFC_COORDSYS_0	01030000A034BF0D00010000000B00000048DE226D9D2B42C0C8031957EBE22BC0E11FD26F5F07DEBFDCC550217D0B42C0C8031957EBE22BC0E11FD26F5F07DEBFDCC550217D0B42C0F8364C8A1E162DC0E11FD26F5F07DEBFDCC550217D2B42C0F8364C8A1E162DC0E11FD26F5F07DEBFDCC550217D2B42C02CA2779C41BE32C0E11FD26F5F07DEBFC8A452BB871E42C02CA2779C41BE32C0E11FD26F5F07DEBFC8A452BB871E42C00C6B9D313ADD32C0E11FD26F5F07DEBF788CEF4DD96A40C0286C9D313ADD32C0E11FD26F5F07DEBF788CEF4DD96A40C068550ABE186B28C0E11FD26F5F07DEBF48DE226D9D2B42C068550ABE186B28C0E11FD26F5F07DEBF48DE226D9D2B42C0C8031957EBE22BC0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6OX	IFC_COORDSYS_0	01030000A034BF0D00010000000B0000007827873AC9F145C0C8AB17E570162DC0E11FD26F5F07DEBF7827873AC9F145C09878E4B13DE32BC0E11FD26F5F07DEBFAC4489D303D245C09878E4B13DE32BC0E11FD26F5F07DEBFAC4489D303D245C068550ABE186B28C0E11FD26F5F07DEBFAA4489D3039247C068550ABE186B28C0E11FD26F5F07DEBFAA4489D3039247C024D2B1DF81DE32C0E11FD26F5F07DEBF4CF0F1BB8BDE45C024D2B1DF81DE32C0E11FD26F5F07DEBF4CF0F1BB8BDE45C0DC2BE7C96ABE32C0E11FD26F5F07DEBF7827873AC9D145C0DC2BE7C96ABE32C0E11FD26F5F07DEBF7827873AC9D145C0C8AB17E570162DC0E11FD26F5F07DEBF7827873AC9F145C0C8AB17E570162DC0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6Od	IFC_COORDSYS_0	01030000A034BF0D00010000000B000000A8921DEE495842C0F8364C8A1E162DC0E11FD26F5F07DEBFA8921DEE495842C0C8031957EBE22BC0E11FD26F5F07DEBF14ABEF396A3842C0C8031957EBE22BC0E11FD26F5F07DEBF14ABEF396A3842C068550ABE186B28C0E11FD26F5F07DEBF14ABEF396AF843C068550ABE186B28C0E11FD26F5F07DEBF14ABEF396AF843C024D2B1DF81DE32C0E11FD26F5F07DEBF300BB921EE4442C024D2B1DF81DE32C0E11FD26F5F07DEBF300BB921EE4442C02CA2779C41BE32C0E11FD26F5F07DEBFA8921DEE493842C02CA2779C41BE32C0E11FD26F5F07DEBFA8921DEE493842C0F8364C8A1E162DC0E11FD26F5F07DEBFA8921DEE495842C0F8364C8A1E162DC0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6Ox	IFC_COORDSYS_0	01030000A034BF0D00010000000B000000AAF41A8B648B49C088722263BC162DC0E11FD26F5F07DEBFAAF41A8B648B49C0583FEF2F89E32BC0E11FD26F5F07DEBF4ADE226D9D6B49C0583FEF2F89E32BC0E11FD26F5F07DEBF4ADE226D9D6B49C068550ABE186B28C0E11FD26F5F07DEBF4ADE226D9D2B4BC068550ABE186B28C0E11FD26F5F07DEBF4ADE226D9D2B4BC024D2B1DF81DE32C0E11FD26F5F07DEBFCAA95055257849C024D2B1DF81DE32C0E11FD26F5F07DEBFCAA95055257849C08CB556F793BE32C0E11FD26F5F07DEBF4ADE226D9D6B49C08CB556F793BE32C0E11FD26F5F07DEBF4ADE226D9D6B49C088722263BC162DC0E11FD26F5F07DEBFAAF41A8B648B49C088722263BC162DC0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6Oy	IFC_COORDSYS_0	01030000A034BF0D00010000000B0000007A1156A0D05E49C0583FEF2F89E32BC0E11FD26F5F07DEBFE2274EBE973E49C0583FEF2F89E32BC0E11FD26F5F07DEBFE2274EBE973E49C088722263BC162DC0E11FD26F5F07DEBF7A1156A0D05E49C088722263BC162DC0E11FD26F5F07DEBF7A1156A0D05E49C08CB556F793BE32C0E11FD26F5F07DEBF6243EAEEBE5149C08CB556F793BE32C0E11FD26F5F07DEBF6243EAEEBE5149C024D2B1DF81DE32C0E11FD26F5F07DEBF7A1156A0D09E47C024D2B1DF81DE32C0E11FD26F5F07DEBF7A1156A0D09E47C068550ABE186B28C0E11FD26F5F07DEBF7A1156A0D05E49C068550ABE186B28C0E11FD26F5F07DEBF7A1156A0D05E49C0583FEF2F89E32BC0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6Ok	IFC_COORDSYS_0	01030000A034BF0D00010000000B00000090374F8CC9233DC08844F21A1ECE2BC0E11FD26F5F07DEBFF8FEEF7592E33CC08844F21A1ECE2BC0E11FD26F5F07DEBFF8FEEF7592E33CC0C077254E51012DC0E11FD26F5F07DEBFF8FEEF7592233DC0D0256D2FCC152DC0E11FD26F5F07DEBFF8FEEF7592233DC08018086F18BE32C0E11FD26F5F07DEBFB82C9C45E4093DC08018086F18BE32C0E11FD26F5F07DEBFB82C9C45E4093DC0286C9D313ADD32C0E11FD26F5F07DEBF50BF0913E4A239C0286C9D313ADD32C0E11FD26F5F07DEBF50BF0913E4A239C068550ABE186B28C0E11FD26F5F07DEBF90374F8CC9233DC068550ABE186B28C0E11FD26F5F07DEBF90374F8CC9233DC08844F21A1ECE2BC0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6OY	IFC_COORDSYS_0	01030000A034BF0D00010000000B000000E077BC0637C545C09878E4B13DE32BC0E11FD26F5F07DEBFAC5ABA6DFCA445C09878E4B13DE32BC0E11FD26F5F07DEBFAC5ABA6DFCA445C0C8AB17E570162DC0E11FD26F5F07DEBFAC5ABA6DFCC445C0C8AB17E570162DC0E11FD26F5F07DEBFAC5ABA6DFCC445C0DC2BE7C96ABE32C0E11FD26F5F07DEBFE4898B5525B845C0DC2BE7C96ABE32C0E11FD26F5F07DEBFE4898B5525B845C024D2B1DF81DE32C0E11FD26F5F07DEBFE077BC06370544C024D2B1DF81DE32C0E11FD26F5F07DEBFE077BC06370544C068550ABE186B28C0E11FD26F5F07DEBFE077BC0637C545C068550ABE186B28C0E11FD26F5F07DEBFE077BC0637C545C09878E4B13DE32BC0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6NJ	IFC_COORDSYS_0	01030000A034BF0D00010000000B000000F80BE087304A36C0287CABA07E112DC0E11FD26F5F07DEBFF80BE087304A36C0F048786D4BDE2BC0E11FD26F5F07DEBFB82570794A0936C0F048786D4BDE2BC0E11FD26F5F07DEBFB82570794A0936C068550ABE186B28C0E11FD26F5F07DEBFB82570794A8939C068550ABE186B28C0E11FD26F5F07DEBFB82570794A8939C0286C9D313ADD32C0E11FD26F5F07DEBFA060C016C72336C0286C9D313ADD32C0E11FD26F5F07DEBFA060C016C72336C070BE8E41EFBD32C0E11FD26F5F07DEBFB82570794A0936C070BE8E41EFBD32C0E11FD26F5F07DEBFB82570794A0936C0287CABA07E112DC0E11FD26F5F07DEBFF80BE087304A36C0287CABA07E112DC0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6Oj	IFC_COORDSYS_0	01030000A034BF0D00010000000B0000009098890F2C7D3DC0C077254E51012DC0E11FD26F5F07DEBF9098890F2C7D3DC08844F21A1ECE2BC0E11FD26F5F07DEBF28D1E825633D3DC08844F21A1ECE2BC0E11FD26F5F07DEBF28D1E825633D3DC068550ABE186B28C0E11FD26F5F07DEBFACBF22810C5E40C068550ABE186B28C0E11FD26F5F07DEBFACBF22810C5E40C0286C9D313ADD32C0E11FD26F5F07DEBF80F96812B1563DC0286C9D313ADD32C0E11FD26F5F07DEBF80F96812B1563DC08018086F18BE32C0E11FD26F5F07DEBF9098890F2C3D3DC08018086F18BE32C0E11FD26F5F07DEBF9098890F2C3D3DC0C077254E51012DC0E11FD26F5F07DEBF9098890F2C7D3DC0C077254E51012DC0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6NK	IFC_COORDSYS_0	01030000A034BF0D00010000000B000000208CD6DFB0EF35C0F048786D4BDE2BC0E11FD26F5F07DEBF607246EE96B035C0F048786D4BDE2BC0E11FD26F5F07DEBF607246EE96B035C0287CABA07E112DC0E11FD26F5F07DEBF208CD6DFB0EF35C0287CABA07E112DC0E11FD26F5F07DEBF208CD6DFB0EF35C070BE8E41EFBD32C0E11FD26F5F07DEBFD093F349FAD635C070BE8E41EFBD32C0E11FD26F5F07DEBFD093F349FAD635C02CA074D5AADA32C0E11FD26F5F07DEBF208CD6DFB06F32C02CA074D5AADA32C0E11FD26F5F07DEBF208CD6DFB06F32C068550ABE186B28C0E11FD26F5F07DEBF208CD6DFB0EF35C068550ABE186B28C0E11FD26F5F07DEBF208CD6DFB0EF35C0F048786D4BDE2BC0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6NP	IFC_COORDSYS_0	01030000A034BF0D00010000000B00000040E40F52C17A2EC0287CABA07E112DC0E11FD26F5F07DEBF40E40F52C17A2EC0F048786D4BDE2BC0E11FD26F5F07DEBF904D4EE510B32DC0F048786D4BDE2BC0E11FD26F5F07DEBF904D4EE510B32DC068550ABE186B28C0E11FD26F5F07DEBF88F23C46175632C068550ABE186B28C0E11FD26F5F07DEBF88F23C46175632C02CA074D5AADA32C0E11FD26F5F07DEBF30C547338CE02DC02CA074D5AADA32C0E11FD26F5F07DEBF30C547338CE02DC024052914C6BD32C0E11FD26F5F07DEBF904D4EE510B32DC024052914C6BD32C0E11FD26F5F07DEBF904D4EE510B32DC0287CABA07E112DC0E11FD26F5F07DEBF40E40F52C17A2EC0287CABA07E112DC0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6Ot	IFC_COORDSYS_0	01030000A034BF0D00010000000B0000008A99892629EC4CC0686545C1E0E32BC0E11FD26F5F07DEBF4AED406DFCC44CC0686545C1E0E32BC0E11FD26F5F07DEBF4AED406DFCC44CC0A09878F413172DC0E11FD26F5F07DEBF72DAB99F2AF34CC0A09878F413172DC0E11FD26F5F07DEBF72DAB99F2AF34CC00429B924BDBE32C0E11FD26F5F07DEBF1289468858EB4CC00429B924BDBE32C0E11FD26F5F07DEBF1289468858EB4CC024D2B1DF81DE32C0E11FD26F5F07DEBF12ABEF396A384BC024D2B1DF81DE32C0E11FD26F5F07DEBF12ABEF396A384BC068550ABE186B28C0E11FD26F5F07DEBF8A99892629EC4CC068550ABE186B28C0E11FD26F5F07DEBF8A99892629EC4CC0686545C1E0E32BC0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6NV	IFC_COORDSYS_0	01030000A034BF0D00010000000C0000002856DF73D4F035C0D057762BA64822C0E11FD26F5F07DEBF680CDCB67AB035C0D057762BA64822C0E11FD26F5F07DEBF680CDCB67AB035C0680F4036204A23C0E11FD26F5F07DEBFA81A580E1A4731C0680F4036204A23C0E11FD26F5F07DEBFA81A580E1A4731C020937474305613C0E11FD26F5F07DEBFD0CE647C4E4F32C020937474305613C0E11FD26F5F07DEBFA83BEC3AC56332C020937474305613C0E11FD26F5F07DEBFA83BEC3AC56332C030FB22BC115113C0E11FD26F5F07DEBF18B0DF90FCD635C030FB22BC115113C0E11FD26F5F07DEBF18B0DF90FCD635C080432FD689C413C0E11FD26F5F07DEBF2856DF73D4F035C080432FD689C413C0E11FD26F5F07DEBF2856DF73D4F035C0D057762BA64822C0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6NC	IFC_COORDSYS_0	01030000A034BF0D000100000009000000BC792B8E702B42C028CB08BE514922C0E11FD26F5F07DEBFBC792B8E700B42C028CB08BE514922C0E11FD26F5F07DEBFBC792B8E700B42C0680F4036204A23C0E11FD26F5F07DEBF588452524AAF3FC0680F4036204A23C0E11FD26F5F07DEBF588452524AAF3FC030FB22BC115113C0E11FD26F5F07DEBF38D72A7BB11E42C030FB22BC115113C0E11FD26F5F07DEBF38D72A7BB11E42C040DB96D3CFC513C0E11FD26F5F07DEBFBC792B8E702B42C040DB96D3CFC513C0E11FD26F5F07DEBFBC792B8E702B42C028CB08BE514922C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048fI	IFC_COORDSYS_0	01030000A034BF0D00010000001300000051A9037F0A1650C030B03E8568001BC0E11FD26F5F07DEBF51A9037F0A1650C068133305CC9422C0E11FD26F5F07DEBFA2A11379631F4EC068133305CC9422C0E11FD26F5F07DEBFA2A11379631F4EC0D0EEFB6B85611CC0E11FD26F5F07DEBFA2A11379631F4EC0B080FF248F611AC0E11FD26F5F07DEBF32FB207287324EC0B080FF248F611AC0E11FD26F5F07DEBF32FB207287324EC0B080FF248F6119C0E11FD26F5F07DEBF32FA53A5BA354EC0B080FF248F6119C0E11FD26F5F07DEBF32FA53A5BA354EC050B9B5D2EB4715C0E11FD26F5F07DEBF32FB207287324EC050B9B5D2EB4715C0E11FD26F5F07DEBF32FB207287324EC030EA6191DF3D13C0E11FD26F5F07DEBFA20F302A8DA24EC030EA6191DF3D13C0E11FD26F5F07DEBF22E08D90F3284FC030EA6191DF3D13C0E11FD26F5F07DEBF9AB0EBF659AF4FC030EA6191DF3D13C0E11FD26F5F07DEBF51A9037F0A1650C030EA6191DF3D13C0E11FD26F5F07DEBF51A9037F0A1650C070BA1529D93D1AC0E11FD26F5F07DEBF5A6D1BDCACEE4EC070BA1529D93D1AC0E11FD26F5F07DEBF5A6D1BDCACEE4EC030B03E8568001BC0E11FD26F5F07DEBF51A9037F0A1650C030B03E8568001BC0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048kF	IFC_COORDSYS_0	01030000A034BF0D0001000000140000008078F527AB7011C010473CE7B9421BC0E11FD26F5F07DEBF8078F527AB7011C0500A65D97D9422C0E11FD26F5F07DEBF0010C12DEE49CFBF500A65D97D9422C0E11FD26F5F07DEBF0010C12DEE49CFBFF8554C4F5CCA21C0E11FD26F5F07DEBF0010C12DEE49CFBFF04B3A66D0231CC0E11FD26F5F07DEBF0010C12DEE49CFBF0014A9FB295C1AC0E11FD26F5F07DEBF008ACA1DCE76DCBF0014A9FB295C1AC0E11FD26F5F07DEBF008ACA1DCE76DCBF008AC19F9A9915C0E11FD26F5F07DEBF001497A2CF95D9BF008AC19F9A9915C0E11FD26F5F07DEBF001497A2CF95D9BF409498430BD714C0E11FD26F5F07DEBF0088505BB6FDCFBF409498430BD714C0E11FD26F5F07DEBF0088505BB6FDCFBF301739B28C5C13C0E11FD26F5F07DEBF00864FEC40D6F3BF301739B28C5C13C0E11FD26F5F07DEBFC0CA04DC865102C0301739B28C5C13C0E11FD26F5F07DEBF40D2E141EDB70AC0301739B28C5C13C0E11FD26F5F07DEBF8078F527AB7011C0301739B28C5C13C0E11FD26F5F07DEBF8078F527AB7011C05051138B2A801AC0E11FD26F5F07DEBF00C9B3771AC1FDBF5051138B2A801AC0E11FD26F5F07DEBF00C9B3771AC1FDBF10473CE7B9421BC0E11FD26F5F07DEBF8078F527AB7011C010473CE7B9421BC0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048f3	IFC_COORDSYS_0	01030000A034BF0D000100000012000000755CA765852252C0A07850A9EECA21C0E11FD26F5F07DEBF755CA765852252C0809C9623A89C22C0E11FD26F5F07DEBF896A378D2C1C51C0809C9623A89C22C0E11FD26F5F07DEBF896A378D2C1C51C0A0523EB9D11A1BC0E11FD26F5F07DEBF65DE8E3123BC51C0A0523EB9D11A1BC0E11FD26F5F07DEBF65DE8E3123BC51C0E05C155D42581AC0E11FD26F5F07DEBF896A378D2C1C51C0E05C155D42581AC0E11FD26F5F07DEBF896A378D2C1C51C080F870FE635813C0E11FD26F5F07DEBFF110F9E7D55B51C080F870FE635813C0E11FD26F5F07DEBF2DF9271B099F51C080F870FE635813C0E11FD26F5F07DEBF6DE1564E3CE251C080F870FE635813C0E11FD26F5F07DEBFA9C0CB5D8B2252C080F870FE635813C0E11FD26F5F07DEBFA9C0CB5D8B2252C0A09C5720AAE214C0E11FD26F5F07DEBFC5B2259ABE1552C0A09C5720AAE214C0E11FD26F5F07DEBFC5B2259ABE1552C0509823933A7C1AC0E11FD26F5F07DEBF755CA765852252C0509823933A7C1AC0E11FD26F5F07DEBF755CA765852252C0E06D57D8C8671CC0E11FD26F5F07DEBF755CA765852252C0A07850A9EECA21C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048kj	IFC_COORDSYS_0	01030000A034BF0D000100000013000000F05DA33F68DE20C0A833435BDB9422C0E11FD26F5F07DEBFF05DA33F68DE20C0806036B7B6291BC0E11FD26F5F07DEBF905F68FD89DE25C0806036B7B6291BC0E11FD26F5F07DEBF905F68FD89DE25C0C06A0D5B27671AC0E11FD26F5F07DEBFF05DA33F68DE20C0C06A0D5B27671AC0E11FD26F5F07DEBFF05DA33F68DE20C0A086E9DC826713C0E11FD26F5F07DEBF6064167ADCE822C0A086E9DC826713C0E11FD26F5F07DEBF50773460860225C0A086E9DC826713C0E11FD26F5F07DEBF30E804AD0F1C27C0A086E9DC826713C0E11FD26F5F07DEBFA06942DA081229C0A086E9DC826713C0E11FD26F5F07DEBFA06942DA081229C080FBB8E9939514C0E11FD26F5F07DEBF309A05A659AB28C080FBB8E9939514C0E11FD26F5F07DEBF309A05A659AB28C0E05F838CEBCD19C0E11FD26F5F07DEBF406DC0E3AC1129C0E05F838CEBCD19C0E11FD26F5F07DEBF406DC0E3AC1129C040325D3A1A2A1AC0E11FD26F5F07DEBF406DC0E3AC1129C040325D3A1A2A1CC0E11FD26F5F07DEBF406DC0E3AC1129C0E0ACFF4F40C821C0E11FD26F5F07DEBF306B908F9B1129C0A833435BDB9422C0E11FD26F5F07DEBFF05DA33F68DE20C0A833435BDB9422C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048hL	IFC_COORDSYS_0	01030000A034BF0D00010000000800000039B139CCA72550C0F40CE4D129D234C0E11FD26F5F07DEBF39B139CCA72550C078E02608E29E32C0E11FD26F5F07DEBFFDE60179457F50C078E02608E29E32C0E11FD26F5F07DEBFFDE60179457F50C0308D033138A42CC0E11FD26F5F07DEBF39548F320E0C51C0308D033138A42CC0E11FD26F5F07DEBF39548F320E0C51C08430F191E31033C0E11FD26F5F07DEBF39548F320E0C51C0F40CE4D129D234C0E11FD26F5F07DEBF39B139CCA72550C0F40CE4D129D234C0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6Nz	IFC_COORDSYS_0	01030000A034BF0D0001000000090000006A001E78A55E49C048A5F296EF4922C0E11FD26F5F07DEBF6A001E78A53E49C048A5F296EF4922C0E11FD26F5F07DEBF6A001E78A53E49C0680F4036204A23C0E11FD26F5F07DEBF7A1156A0D09E47C0680F4036204A23C0E11FD26F5F07DEBF7A1156A0D09E47C030FB22BC115113C0E11FD26F5F07DEBFDAEE8AF7E65149C030FB22BC115113C0E11FD26F5F07DEBFDAEE8AF7E65149C0301D87AD1CC713C0E11FD26F5F07DEBF6A001E78A55E49C0301D87AD1CC713C0E11FD26F5F07DEBF6A001E78A55E49C048A5F296EF4922C0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6Nu	IFC_COORDSYS_0	01030000A034BF0D000100000009000000080057F4D6F145C0680F4036204A23C0E11FD26F5F07DEBF080057F4D6F145C0E891133C9D4922C0E11FD26F5F07DEBF1C8293AAA7D245C0E891133C9D4922C0E11FD26F5F07DEBF1C8293AAA7D245C0E0FAC8F777C613C0E11FD26F5F07DEBFC09B92C4B3DE45C0E0FAC8F777C613C0E11FD26F5F07DEBFC09B92C4B3DE45C030FB22BC115113C0E11FD26F5F07DEBFAA4489D3039247C030FB22BC115113C0E11FD26F5F07DEBFAA4489D3039247C0680F4036204A23C0E11FD26F5F07DEBF080057F4D6F145C0680F4036204A23C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048kp	IFC_COORDSYS_0	01030000A034BF0D00010000000E0000000080B7521926DABF50626F0D006033C0E11FD26F5F07DEBF0080B7521926DABF50626F0D00E032C0E11FD26F5F07DEBF00E846B25A8AD0BF50626F0D00E032C0E11FD26F5F07DEBF00E846B25A8AD0BF988677D39BD931C0E11FD26F5F07DEBF009E826AE2DFD8BF988677D39BD931C0E11FD26F5F07DEBF009E826AE2DFD8BF645344A068A631C0E11FD26F5F07DEBF00FCAB9CD78ECEBF645344A068A631C0E11FD26F5F07DEBF00FCAB9CD78ECEBFFC302EA7991931C0E11FD26F5F07DEBF00FCAB9CD78ECEBFBC04EF4B2D0E31C0E11FD26F5F07DEBF404EBBD74E5A11C0BC04EF4B2D0E31C0E11FD26F5F07DEBF404EBBD74E5A11C07C3C6A7F140035C0E11FD26F5F07DEBF00E846B25A8AD0BF7C3C6A7F140035C0E11FD26F5F07DEBF00E846B25A8AD0BF50626F0D006033C0E11FD26F5F07DEBF0080B7521926DABF50626F0D006033C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048f9	IFC_COORDSYS_0	01030000A034BF0D00010000000D0000009AA0AEC5EE344EC0747176ECFA5133C0E11FD26F5F07DEBF02377E00BD314EC0747176ECFA5133C0E11FD26F5F07DEBF02377E00BD314EC0747176ECFAD132C0E11FD26F5F07DEBF6A2EAB61AB334EC0747176ECFAD132C0E11FD26F5F07DEBF6A2EAB61AB334EC058D846CFFA9131C0E11FD26F5F07DEBF72B89C2B971E4EC058D846CFFA9131C0E11FD26F5F07DEBF72B89C2B971E4EC07CF2F728E80331C0E11FD26F5F07DEBFA1C234FCB11550C07CF2F728E80331C0E11FD26F5F07DEBF39B139CCA71550C0FC9A580047E534C0E11FD26F5F07DEBFD2553D83853E4EC0381997FB30E534C0E11FD26F5F07DEBFD2553D83853E4EC0CC8D56ECFA5134C0E11FD26F5F07DEBF9AA0AEC5EE344EC0CC8D56ECFA5134C0E11FD26F5F07DEBF9AA0AEC5EE344EC0747176ECFA5133C0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6Na	IFC_COORDSYS_0	01030000A034BF0D00010000000A000000F2C15239C4FC4CC098A97F17474A22C0E11FD26F5F07DEBF0AE5F51F0BC54CC098A97F17474A22C0E11FD26F5F07DEBF0AE5F51F0BC54CC0680F4036204A23C0E11FD26F5F07DEBF2A59371BE5CC4BC0680F4036204A23C0E11FD26F5F07DEBF2A59371BE5CC4BC0706B396A593213C0E11FD26F5F07DEBFBA1CEC9080EB4CC0706B396A593213C0E11FD26F5F07DEBFBA1CEC9080EB4CC0704FD1F4BDC713C0E11FD26F5F07DEBFF2C15239C4FC4CC0704FD1F4BDC713C0E11FD26F5F07DEBFF2C15239C4FC4CC00015E8FE66611AC0E11FD26F5F07DEBFF2C15239C4FC4CC098A97F17474A22C0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6N_	IFC_COORDSYS_0	01030000A034BF0D0001000000090000003ACDEA44728B49C0680F4036204A23C0E11FD26F5F07DEBF3ACDEA44728B49C048A5F296EF4922C0E11FD26F5F07DEBF3ACDEA44726B49C048A5F296EF4922C0E11FD26F5F07DEBF3ACDEA44726B49C0301D87AD1CC713C0E11FD26F5F07DEBF4255F15D4D7849C0301D87AD1CC713C0E11FD26F5F07DEBF4255F15D4D7849C0706B396A593213C0E11FD26F5F07DEBF828C3FC701974AC0706B396A593213C0E11FD26F5F07DEBF828C3FC701974AC0680F4036204A23C0E11FD26F5F07DEBF3ACDEA44728B49C0680F4036204A23C0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6Nt	IFC_COORDSYS_0	01030000A034BF0D00010000000B00000050B5C6DDDAC545C0E891133C9D4922C0E11FD26F5F07DEBF3C338A270AA545C0E891133C9D4922C0E11FD26F5F07DEBF3C338A270AA545C0680F4036204A23C0E11FD26F5F07DEBFF42504E8B19944C0680F4036204A23C0E11FD26F5F07DEBFF42504E8B19944C030FB22BC115113C0E11FD26F5F07DEBFC06F2EBC671D45C030FB22BC115113C0E11FD26F5F07DEBFC06F2EBC671D45C040CB7F4BD44613C0E11FD26F5F07DEBF5C352C5E4DB845C040CB7F4BD44613C0E11FD26F5F07DEBF5C352C5E4DB845C0E0FAC8F777C613C0E11FD26F5F07DEBF50B5C6DDDAC545C0E0FAC8F777C613C0E11FD26F5F07DEBF50B5C6DDDAC545C0E891133C9D4922C0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6NB	IFC_COORDSYS_0	01030000A034BF0D00010000000A000000483F9DF14A7D3DC0680F4036204A23C0E11FD26F5F07DEBF483F9DF14A7D3DC0D0B72963FF4822C0E11FD26F5F07DEBFF022AC40A13D3DC0D0B72963FF4822C0E11FD26F5F07DEBFF022AC40A13D3DC000C064AF27C513C0E11FD26F5F07DEBF40086590FC563DC000C064AF27C513C0E11FD26F5F07DEBF40086590FC563DC020937474305613C0E11FD26F5F07DEBF00714B1FBF8C3FC020937474305613C0E11FD26F5F07DEBFD8EBB8B8B0953FC020937474305613C0E11FD26F5F07DEBFD8EBB8B8B0953FC0680F4036204A23C0E11FD26F5F07DEBF483F9DF14A7D3DC0680F4036204A23C0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6N6	IFC_COORDSYS_0	01030000A034BF0D000100000009000000588912A707243DC0D0B72963FF4822C0E11FD26F5F07DEBFB0A50358B1E33CC0D0B72963FF4822C0E11FD26F5F07DEBFB0A50358B1E33CC0680F4036204A23C0E11FD26F5F07DEBFE8C6C444F7CB3AC0680F4036204A23C0E11FD26F5F07DEBFE8C6C444F7CB3AC020937474305613C0E11FD26F5F07DEBF703B98C32F0A3DC020937474305613C0E11FD26F5F07DEBF703B98C32F0A3DC000C064AF27C513C0E11FD26F5F07DEBF588912A707243DC000C064AF27C513C0E11FD26F5F07DEBF588912A707243DC0D0B72963FF4822C0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6Nn	IFC_COORDSYS_0	01030000A034BF0D0001000000090000008846F85A3D5842C0680F4036204A23C0E11FD26F5F07DEBF8846F85A3D5842C028CB08BE514922C0E11FD26F5F07DEBF8846F85A3D3842C028CB08BE514922C0E11FD26F5F07DEBF8846F85A3D3842C040DB96D3CFC513C0E11FD26F5F07DEBF9C3D91E1174542C040DB96D3CFC513C0E11FD26F5F07DEBF9C3D91E1174542C020937474305613C0E11FD26F5F07DEBF64F8FE54EF6343C020937474305613C0E11FD26F5F07DEBF64F8FE54EF6343C0680F4036204A23C0E11FD26F5F07DEBF8846F85A3D5842C0680F4036204A23C0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6N0	IFC_COORDSYS_0	01030000A034BF0D00010000000900000000A67550144A36C0680F4036204A23C0E11FD26F5F07DEBF00A67550144A36C0D057762BA64822C0E11FD26F5F07DEBFC0EF780D6E0A36C0D057762BA64822C0E11FD26F5F07DEBFC0EF780D6E0A36C080432FD689C413C0E11FD26F5F07DEBFE87CAC5DC92336C080432FD689C413C0E11FD26F5F07DEBFE87CAC5DC92336C020937474305613C0E11FD26F5F07DEBF9893E94A786138C020937474305613C0E11FD26F5F07DEBF9893E94A786138C0680F4036204A23C0E11FD26F5F07DEBF00A67550144A36C0680F4036204A23C0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6NQ	IFC_COORDSYS_0	01030000A034BF0D00010000000A00000090950CE5957A2EC0680F4036204A23C0E11FD26F5F07DEBF90950CE5957A2EC0B83ED187554822C0E11FD26F5F07DEBFE00946FE81B02DC0B83ED187554822C0E11FD26F5F07DEBFE00946FE81B02DC0E0D47EF7372A1CC0E11FD26F5F07DEBFE00946FE81B02DC070DA9843DEC313C0E11FD26F5F07DEBF5042D4552CE12DC070DA9843DEC313C0E11FD26F5F07DEBF5042D4552CE12DC020937474305613C0E11FD26F5F07DEBF1081BE74802D31C020937474305613C0E11FD26F5F07DEBF1081BE74802D31C0680F4036204A23C0E11FD26F5F07DEBF90950CE5957A2EC0680F4036204A23C0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6NZ	IFC_COORDSYS_0	01030000A034BF0D0001000000050000006A8C6A4E18C04BC0906C396A593213C0E11FD26F5F07DEBF6A8C6A4E18C04BC0D80E4036204A23C0E11FD26F5F07DEBF42590C94CEA34AC0D80E4036204A23C0E11FD26F5F07DEBF42590C94CEA34AC0906C396A593213C0E11FD26F5F07DEBF6A8C6A4E18C04BC0906C396A593213C0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6No	IFC_COORDSYS_0	01030000A034BF0D00010000000700000030C5CB21BC7043C0680F4036204A23C0E11FD26F5F07DEBF30C5CB21BC7043C020937474305613C0E11FD26F5F07DEBF788EB3A7B9F543C020937474305613C0E11FD26F5F07DEBF788EB3A7B9F543C030FB22BC115113C0E11FD26F5F07DEBF2859371BE58C44C030FB22BC115113C0E11FD26F5F07DEBF2859371BE58C44C0680F4036204A23C0E11FD26F5F07DEBF30C5CB21BC7043C0680F4036204A23C0E11FD26F5F07DEBF
first_floor	1BUg4a4jr0B9Q5NnDgB6N5	IFC_COORDSYS_0	01030000A034BF0D000100000005000000D82C2BAB5DB23AC0B0917474305613C0E11FD26F5F07DEBFD82C2BAB5DB23AC0F80D4036204A23C0E11FD26F5F07DEBF882C83E4117B38C0F80D4036204A23C0E11FD26F5F07DEBF882C83E4117B38C0B0917474305613C0E11FD26F5F07DEBFD82C2BAB5DB23AC0B0917474305613C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048kT	IFC_COORDSYS_0	01030000A034BF0D000100000007000000F05DA33F68DE20C0A0E046B84ECE02C0E11FD26F5F07DEBFF05DA33F68DE20C00060CB53C288CDBFE11FD26F5F07DEBFA06942DA081229C00060CB53C288CDBFE11FD26F5F07DEBFA06942DA081229C0803AACF1480202C0E11FD26F5F07DEBFE088EE88E2D128C0803AACF1480202C0E11FD26F5F07DEBFE088EE88E2D128C0A0E046B84ECE02C0E11FD26F5F07DEBFF05DA33F68DE20C0A0E046B84ECE02C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048kU	IFC_COORDSYS_0	01030000A034BF0D00010000000500000000E4FFFFFFFFCFBF00CCE64694CD02C0E11FD26F5F07DEBF00E4FFFFFFFFCFBF002C00000000D0BFE11FD26F5F07DEBF6079F527AB7011C0002C00000000D0BFE11FD26F5F07DEBF6079F527AB7011C000CCE64694CD02C0E11FD26F5F07DEBF00E4FFFFFFFFCFBF00CCE64694CD02C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048k8	IFC_COORDSYS_0	01030000A034BF0D00010000000A000000F05DA33F68DE20C0C099A290244937C0E11FD26F5F07DEBFF05DA33F68DE20C0FC6CBB21A11A37C0E11FD26F5F07DEBFF05DA33F68DE20C0846DACB4C13435C0E11FD26F5F07DEBF4080F1E91F1129C0846DACB4C13435C0E11FD26F5F07DEBF4080F1E91F1129C0C822E09DF14737C0E11FD26F5F07DEBF4080F1E91F9128C0C822E09DF14737C0E11FD26F5F07DEBF4080F1E91F9128C0D455E776FE4C37C0E11FD26F5F07DEBFF0A1A28ED95D21C0D455E776FE4C37C0E11FD26F5F07DEBFF0A1A28ED95D21C0C099A290244937C0E11FD26F5F07DEBFF05DA33F68DE20C0C099A290244937C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048ks	IFC_COORDSYS_0	01030000A034BF0D000100000009000000404EBBD74E5A11C0145118C7F53A35C0E11FD26F5F07DEBF404EBBD74E5A11C0486A0E377F4637C0E11FD26F5F07DEBF604FB3DD6A5A10C0486A0E377F4637C0E11FD26F5F07DEBF604FB3DD6A5A10C0C87436A8704F37C0E11FD26F5F07DEBF007423592D45E0BFC87436A8704F37C0E11FD26F5F07DEBF007423592D45E0BF8CDDF558244537C0E11FD26F5F07DEBF00E846B25A8AD0BF8CDDF558244537C0E11FD26F5F07DEBF00E846B25A8AD0BF145118C7F53A35C0E11FD26F5F07DEBF404EBBD74E5A11C0145118C7F53A35C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048kr	IFC_COORDSYS_0	01030000A034BF0D0001000000070000008080684564C428C068655E3C302033C0E11FD26F5F07DEBF8080684564C428C0A019216DE05933C0E11FD26F5F07DEBF4080F1E91F1129C0A019216DE05933C0E11FD26F5F07DEBF4080F1E91F1129C00859FE6CE0F934C0E11FD26F5F07DEBFF05DA33F68DE20C00859FE6CE0F934C0E11FD26F5F07DEBFF05DA33F68DE20C068655E3C302033C0E11FD26F5F07DEBF8080684564C428C068655E3C302033C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048fC	IFC_COORDSYS_0	01030000A034BF0D00010000000A00000025690C80DE1852C07082A9B0681C33C0E11FD26F5F07DEBF25690C80DE1852C0D47D30D7415233C0E11FD26F5F07DEBF959FEC43F21652C0D47D30D7415233C0E11FD26F5F07DEBF959FEC43F21652C0B899BA20445234C0E11FD26F5F07DEBF39F7E498741252C0B899BA20445234C0E11FD26F5F07DEBF39F7E498741252C000AD1B735EE534C0E11FD26F5F07DEBF39548F320E2C51C000AD1B735EE534C0E11FD26F5F07DEBF39548F320E1C51C000AD1B735EE534C0E11FD26F5F07DEBF39548F320E1C51C07082A9B0681C33C0E11FD26F5F07DEBF25690C80DE1852C07082A9B0681C33C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048kv	IFC_COORDSYS_0	01030000A034BF0D00010000000500000080C1A53CD2D122C0A0D4C58B46B00AC0E11FD26F5F07DEBF80C1A53CD2D122C0F0F826E7590B13C0E11FD26F5F07DEBF405FA33F68DE20C0F0F826E7590B13C0E11FD26F5F07DEBF405FA33F68DE20C0A0D4C58B46B00AC0E11FD26F5F07DEBF80C1A53CD2D122C0A0D4C58B46B00AC0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048k2	IFC_COORDSYS_0	01030000A034BF0D000100000005000000C060A43716140BC0208876BC630013C0E11FD26F5F07DEBFC060A43716140BC000616977349A0AC0E11FD26F5F07DEBFE078F527AB7011C000616977349A0AC0E11FD26F5F07DEBFE078F527AB7011C0208876BC630013C0E11FD26F5F07DEBFC060A43716140BC0208876BC630013C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048kk	IFC_COORDSYS_0	01030000A034BF0D000100000005000000B2E6D39ACA9C4EC000C5D9A6D78F0AC0E11FD26F5F07DEBFB2E6D39ACA9C4EC040599F9BB6E112C0E11FD26F5F07DEBF9AA11379631F4EC040599F9BB6E112C0E11FD26F5F07DEBF9AA11379631F4EC000C5D9A6D78F0AC0E11FD26F5F07DEBFB2E6D39ACA9C4EC000C5D9A6D78F0AC0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048kw	IFC_COORDSYS_0	01030000A034BF0D000100000005000000500787B7E6FF22C0A0D4C58B46B00AC0E11FD26F5F07DEBF30D2C3227CEB24C0A0D4C58B46B00AC0E11FD26F5F07DEBF30D2C3227CEB24C0F0F826E7590B13C0E11FD26F5F07DEBF500787B7E6FF22C0F0F826E7590B13C0E11FD26F5F07DEBF500787B7E6FF22C0A0D4C58B46B00AC0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048k4	IFC_COORDSYS_0	01030000A034BF0D000100000005000000C03A42E65DF501C0208876BC630013C0E11FD26F5F07DEBF80A6D4D7928EF4BF208876BC630013C0E11FD26F5F07DEBF80A6D4D7928EF4BF00616977349A0AC0E11FD26F5F07DEBFC03A42E65DF501C000616977349A0AC0E11FD26F5F07DEBFC03A42E65DF501C0208876BC630013C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048k1	IFC_COORDSYS_0	01030000A034BF0D00010000000500000040421F4CC45B0AC0208876BC630013C0E11FD26F5F07DEBFC05AC7D1AFAD02C0208876BC630013C0E11FD26F5F07DEBFC05AC7D1AFAD02C000616977349A0AC0E11FD26F5F07DEBF40421F4CC45B0AC000616977349A0AC0E11FD26F5F07DEBF40421F4CC45B0AC0208876BC630013C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048kd	IFC_COORDSYS_0	01030000A034BF0D000100000005000000201AA59D901925C0A0D4C58B46B00AC0E11FD26F5F07DEBF2043946F050527C0A0D4C58B46B00AC0E11FD26F5F07DEBF2043946F050527C0F0F826E7590B13C0E11FD26F5F07DEBF201AA59D901925C0F0F826E7590B13C0E11FD26F5F07DEBF201AA59D901925C0A0D4C58B46B00AC0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048kR	IFC_COORDSYS_0	01030000A034BF0D000100000005000000006ACA00EF1DF3BF208876BC630013C0E11FD26F5F07DEBF0070505BB6FDCFBF208876BC630013C0E11FD26F5F07DEBF0070505BB6FDCFBF00616977349A0AC0E11FD26F5F07DEBF006ACA00EF1DF3BF00616977349A0AC0E11FD26F5F07DEBF006ACA00EF1DF3BF208876BC630013C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048fO	IFC_COORDSYS_0	01030000A034BF0D000100000005000000B1E479D3279C51C0D06BAE083BFC12C0E11FD26F5F07DEBF7125A72FB75E51C0D06BAE083BFC12C0E11FD26F5F07DEBF7125A72FB75E51C0A01D6F3B8DC40AC0E11FD26F5F07DEBFB1E479D3279C51C0A01D6F3B8DC40AC0E11FD26F5F07DEBFB1E479D3279C51C0D06BAE083BFC12C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048f5	IFC_COORDSYS_0	01030000A034BF0D000100000005000000EDCCA8065BDF51C0D06BAE083BFC12C0E11FD26F5F07DEBFB10DD662EAA151C0D06BAE083BFC12C0E11FD26F5F07DEBFB10DD662EAA151C0A01D6F3B8DC40AC0E11FD26F5F07DEBFEDCCA8065BDF51C0A01D6F3B8DC40AC0E11FD26F5F07DEBFEDCCA8065BDF51C0D06BAE083BFC12C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048fK	IFC_COORDSYS_0	01030000A034BF0D0001000000050000001A09EA1FB62E4FC000C5D9A6D78F0AC0E11FD26F5F07DEBFA2878F6797A94FC000C5D9A6D78F0AC0E11FD26F5F07DEBFA2878F6797A94FC040599F9BB6E112C0E11FD26F5F07DEBF1A09EA1FB62E4FC040599F9BB6E112C0E11FD26F5F07DEBF1A09EA1FB62E4FC000C5D9A6D78F0AC0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048kh	IFC_COORDSYS_0	01030000A034BF0D000100000005000000AA388CB94FA84EC000C5D9A6D78F0AC0E11FD26F5F07DEBF22B7310131234FC000C5D9A6D78F0AC0E11FD26F5F07DEBF22B7310131234FC040599F9BB6E112C0E11FD26F5F07DEBFAA388CB94FA84EC040599F9BB6E112C0E11FD26F5F07DEBFAA388CB94FA84EC000C5D9A6D78F0AC0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048f6	IFC_COORDSYS_0	01030000A034BF0D000100000005000000A9C0CB5D8B2252C06095D54154C50AC0E11FD26F5F07DEBFA9C0CB5D8B2252C02069AE083BFC12C0E11FD26F5F07DEBFE5F504961DE551C02069AE083BFC12C0E11FD26F5F07DEBFE5F504961DE551C0401A6F3B8DC40AC0E11FD26F5F07DEBFA9C0CB5D8B2252C06095D54154C50AC0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048kW	IFC_COORDSYS_0	01030000A034BF0D000100000007000000A06942DA081229C050F726E7590B13C0E11FD26F5F07DEBF008C75EA193327C050F726E7590B13C0E11FD26F5F07DEBF008C75EA193327C0E0D7C58B46B00AC0E11FD26F5F07DEBFE088EE88E2D128C0E0D7C58B46B00AC0E11FD26F5F07DEBFE088EE88E2D128C0A067AFDDFECE0AC0E11FD26F5F07DEBFA06942DA081229C0A067AFDDFECE0AC0E11FD26F5F07DEBFA06942DA081229C050F726E7590B13C0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048fV	IFC_COORDSYS_0	01030000A034BF0D00010000000500000069FC4AA0F45851C0A01D6F3B8DC40AC0E11FD26F5F07DEBF69FC4AA0F45851C0D06BAE083BFC12C0E11FD26F5F07DEBF556A378D2C1C51C0D06BAE083BFC12C0E11FD26F5F07DEBF556A378D2C1C51C0A01D6F3B8DC40AC0E11FD26F5F07DEBF69FC4AA0F45851C0A01D6F3B8DC40AC0E11FD26F5F07DEBF
first_floor	1mWTVVwiXDHQKYjSZ048fH	IFC_COORDSYS_0	01030000A034BF0D00010000000500000072D947861CB54FC040599F9BB6E112C0E11FD26F5F07DEBF72D947861CB54FC000C5D9A6D78F0AC0E11FD26F5F07DEBF61A9037F0A1650C000C5D9A6D78F0AC0E11FD26F5F07DEBF61A9037F0A1650C040599F9BB6E112C0E11FD26F5F07DEBF72D947861CB54FC040599F9BB6E112C0E11FD26F5F07DEBF
\.


--
-- Data for Name: rooms; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.rooms (level, _area_id, geom) FROM stdin;
first_floor	1mWTVVwiXDHQKYjSZ048h5	01030000A034BF0D000100000039000000008CEEB16C06C4BFF02F5D4DB8CA28C09A9999999999E93F003E4281DCFDF43F487E89C66BC228C09A9999999999E93F003E4281DCFDF43F387CEC74B3F522C09A9999999999E93F006ED2D5D70BF93F387CEC74B3F522C09A9999999999E93F006ED2D5D70BF93FE0D47EF7372A1CC09A9999999999E93F0000A10A9780793FE0D47EF7372A1CC09A9999999999E93F0000A10A9780793F706ABFFB1B1523C09A9999999999E93F8078F527AB7012C0706ABFFB1B1523C09A9999999999E93F8078F527AB7012C000000000000000009A9999999999E93F70EF2DC7886B20C000000000000000009A9999999999E93F70EF2DC7886B20C0D8CD37AF040023C09A9999999999E93F7045B886699629C0D8CD37AF040023C09A9999999999E93F7045B886699629C0E0D47EF7372A1CC09A9999999999E93FB078EBB99CC92CC0E0D47EF7372A1CC09A9999999999E93FB078EBB99CC92CC068A2B74D2AE822C09A9999999999E93F30BA4A85C7282CC068A2B74D2AE822C09A9999999999E93F30BA4A85C7282CC0003C51E7C38123C09A9999999999E93F5A7B1FAEFE564DC0D03951E7C38123C09A9999999999E93F5A7B1FAEFE564DC010C2720549FE22C09A9999999999E93FF214B94798304DC010C2720549FE22C09A9999999999E93FF214B94798304DC090EA4B71F8621CC09A9999999999E93F7A382FBFE7FD4DC090EA4B71F8621CC09A9999999999E93F7A382FBFE7FD4DC010C2720549FE22C09A9999999999E93F51A9037F0A2650C010C2720549FE22C09A9999999999E93F51A9037F0A2650C0F050B2D75EC91AC09A9999999999E93FB90F6AE5700C51C0F050B2D75EC91AC09A9999999999E93FB90F6AE5700C51C018AA5A87180223C09A9999999999E93F71CFCA12273252C018AA5A87180223C09A9999999999E93F71CFCA12273252C0B05F05658B5D1CC09A9999999999E93F71CFCA12279252C0B05F05658B5D1CC09A9999999999E93F71CFCA12279252C0A07C4F7F92FB22C09A9999999999E93F6148BE185A8752C0A07C4F7F92FB22C09A9999999999E93F6148BE185A8752C070491C4C5FC828C09A9999999999E93F15AF5FB3E79052C070491C4C5FC828C09A9999999999E93F15AF5FB3E79052C0EC5741D9629730C09A9999999999E93F05D1E2877A3252C0EC5741D9629730C09A9999999999E93F05D1E2877A3252C0C8269DCAD13D2CC09A9999999999E93FD154EE9D272352C0C8269DCAD13D2CC09A9999999999E93FD154EE9D272352C0308D033138A42DC09A9999999999E93F390F9FE1D41D51C0308D033138A42DC09A9999999999E93F390F9FE1D41D51C0C8269DCAD13D2CC09A9999999999E93F311A35AC787250C0C8269DCAD13D2CC09A9999999999E93F311A35AC787250C0B4013175957A32C09A9999999999E93F3DC11584372650C0B4013175957A32C09A9999999999E93F3DC11584372650C09836951D5E282CC09A9999999999E93F7A822B086F0C4EC09836951D5E282CC09A9999999999E93F7A822B086F0C4EC0009DFB83C48E28C09A9999999999E93F4A4FF8D43B594DC0009DFB83C48E28C09A9999999999E93F4A4FF8D43B594DC0289D3316882B28C09A9999999999E93FF009AE20BC3129C0289D3316882B28C09A9999999999E93FF009AE20BC3129C090039A7CEE912DC09A9999999999E93F00A177FB2EEA20C090039A7CEE912DC09A9999999999E93F00A177FB2EEA20C060D06649BB5E2CC09A9999999999E93F0098C555DD43CEBF60D06649BB5E2CC09A9999999999E93F0098C555DD43CEBF701BAF05D74F2CC09A9999999999E93F008CEEB16C06C4BF701BAF05D74F2CC09A9999999999E93F008CEEB16C06C4BFF02F5D4DB8CA28C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048ky	01030000A034BF0D000100000005000000105FA33F685E20C0409C1657F7752CC09A9999999999E93F105FA33F685E20C0A881F5AD091B37C09A9999999999E93F6050BBD74E5A12C0A881F5AD091B37C09A9999999999E93F6050BBD74E5A12C0409C1657F7752CC09A9999999999E93F105FA33F685E20C0409C1657F7752CC09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6Oe	01030000A034BF0D00010000000B00000048DE226D9D2B42C0C8031957EBE22BC09A9999999999E93FDCC550217D0B42C0C8031957EBE22BC09A9999999999E93FDCC550217D0B42C0F8364C8A1E162DC09A9999999999E93FDCC550217D2B42C0F8364C8A1E162DC09A9999999999E93FDCC550217D2B42C02CA2779C41BE32C09A9999999999E93FC8A452BB871E42C02CA2779C41BE32C09A9999999999E93FC8A452BB871E42C00C6B9D313ADD32C09A9999999999E93F788CEF4DD96A40C0286C9D313ADD32C09A9999999999E93F788CEF4DD96A40C068550ABE186B28C09A9999999999E93F48DE226D9D2B42C068550ABE186B28C09A9999999999E93F48DE226D9D2B42C0C8031957EBE22BC09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6OX	01030000A034BF0D00010000000B0000007827873AC9F145C0C8AB17E570162DC09A9999999999E93F7827873AC9F145C09878E4B13DE32BC09A9999999999E93FAC4489D303D245C09878E4B13DE32BC09A9999999999E93FAC4489D303D245C068550ABE186B28C09A9999999999E93FAA4489D3039247C068550ABE186B28C09A9999999999E93FAA4489D3039247C024D2B1DF81DE32C09A9999999999E93F4CF0F1BB8BDE45C024D2B1DF81DE32C09A9999999999E93F4CF0F1BB8BDE45C0DC2BE7C96ABE32C09A9999999999E93F7827873AC9D145C0DC2BE7C96ABE32C09A9999999999E93F7827873AC9D145C0C8AB17E570162DC09A9999999999E93F7827873AC9F145C0C8AB17E570162DC09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6Od	01030000A034BF0D00010000000B000000A8921DEE495842C0F8364C8A1E162DC09A9999999999E93FA8921DEE495842C0C8031957EBE22BC09A9999999999E93F14ABEF396A3842C0C8031957EBE22BC09A9999999999E93F14ABEF396A3842C068550ABE186B28C09A9999999999E93F14ABEF396AF843C068550ABE186B28C09A9999999999E93F14ABEF396AF843C024D2B1DF81DE32C09A9999999999E93F300BB921EE4442C024D2B1DF81DE32C09A9999999999E93F300BB921EE4442C02CA2779C41BE32C09A9999999999E93FA8921DEE493842C02CA2779C41BE32C09A9999999999E93FA8921DEE493842C0F8364C8A1E162DC09A9999999999E93FA8921DEE495842C0F8364C8A1E162DC09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6Ox	01030000A034BF0D00010000000B000000AAF41A8B648B49C088722263BC162DC09A9999999999E93FAAF41A8B648B49C0583FEF2F89E32BC09A9999999999E93F4ADE226D9D6B49C0583FEF2F89E32BC09A9999999999E93F4ADE226D9D6B49C068550ABE186B28C09A9999999999E93F4ADE226D9D2B4BC068550ABE186B28C09A9999999999E93F4ADE226D9D2B4BC024D2B1DF81DE32C09A9999999999E93FCAA95055257849C024D2B1DF81DE32C09A9999999999E93FCAA95055257849C08CB556F793BE32C09A9999999999E93F4ADE226D9D6B49C08CB556F793BE32C09A9999999999E93F4ADE226D9D6B49C088722263BC162DC09A9999999999E93FAAF41A8B648B49C088722263BC162DC09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6Oy	01030000A034BF0D00010000000B0000007A1156A0D05E49C0583FEF2F89E32BC09A9999999999E93FE2274EBE973E49C0583FEF2F89E32BC09A9999999999E93FE2274EBE973E49C088722263BC162DC09A9999999999E93F7A1156A0D05E49C088722263BC162DC09A9999999999E93F7A1156A0D05E49C08CB556F793BE32C09A9999999999E93F6243EAEEBE5149C08CB556F793BE32C09A9999999999E93F6243EAEEBE5149C024D2B1DF81DE32C09A9999999999E93F7A1156A0D09E47C024D2B1DF81DE32C09A9999999999E93F7A1156A0D09E47C068550ABE186B28C09A9999999999E93F7A1156A0D05E49C068550ABE186B28C09A9999999999E93F7A1156A0D05E49C0583FEF2F89E32BC09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6Ok	01030000A034BF0D00010000000B00000090374F8CC9233DC08844F21A1ECE2BC09A9999999999E93FF8FEEF7592E33CC08844F21A1ECE2BC09A9999999999E93FF8FEEF7592E33CC0C077254E51012DC09A9999999999E93FF8FEEF7592233DC0D0256D2FCC152DC09A9999999999E93FF8FEEF7592233DC08018086F18BE32C09A9999999999E93FB82C9C45E4093DC08018086F18BE32C09A9999999999E93FB82C9C45E4093DC0286C9D313ADD32C09A9999999999E93F50BF0913E4A239C0286C9D313ADD32C09A9999999999E93F50BF0913E4A239C068550ABE186B28C09A9999999999E93F90374F8CC9233DC068550ABE186B28C09A9999999999E93F90374F8CC9233DC08844F21A1ECE2BC09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6OY	01030000A034BF0D00010000000B000000E077BC0637C545C09878E4B13DE32BC09A9999999999E93FAC5ABA6DFCA445C09878E4B13DE32BC09A9999999999E93FAC5ABA6DFCA445C0C8AB17E570162DC09A9999999999E93FAC5ABA6DFCC445C0C8AB17E570162DC09A9999999999E93FAC5ABA6DFCC445C0DC2BE7C96ABE32C09A9999999999E93FE4898B5525B845C0DC2BE7C96ABE32C09A9999999999E93FE4898B5525B845C024D2B1DF81DE32C09A9999999999E93FE077BC06370544C024D2B1DF81DE32C09A9999999999E93FE077BC06370544C068550ABE186B28C09A9999999999E93FE077BC0637C545C068550ABE186B28C09A9999999999E93FE077BC0637C545C09878E4B13DE32BC09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6NJ	01030000A034BF0D00010000000B000000F80BE087304A36C0287CABA07E112DC09A9999999999E93FF80BE087304A36C0F048786D4BDE2BC09A9999999999E93FB82570794A0936C0F048786D4BDE2BC09A9999999999E93FB82570794A0936C068550ABE186B28C09A9999999999E93FB82570794A8939C068550ABE186B28C09A9999999999E93FB82570794A8939C0286C9D313ADD32C09A9999999999E93FA060C016C72336C0286C9D313ADD32C09A9999999999E93FA060C016C72336C070BE8E41EFBD32C09A9999999999E93FB82570794A0936C070BE8E41EFBD32C09A9999999999E93FB82570794A0936C0287CABA07E112DC09A9999999999E93FF80BE087304A36C0287CABA07E112DC09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6Oj	01030000A034BF0D00010000000B0000009098890F2C7D3DC0C077254E51012DC09A9999999999E93F9098890F2C7D3DC08844F21A1ECE2BC09A9999999999E93F28D1E825633D3DC08844F21A1ECE2BC09A9999999999E93F28D1E825633D3DC068550ABE186B28C09A9999999999E93FACBF22810C5E40C068550ABE186B28C09A9999999999E93FACBF22810C5E40C0286C9D313ADD32C09A9999999999E93F80F96812B1563DC0286C9D313ADD32C09A9999999999E93F80F96812B1563DC08018086F18BE32C09A9999999999E93F9098890F2C3D3DC08018086F18BE32C09A9999999999E93F9098890F2C3D3DC0C077254E51012DC09A9999999999E93F9098890F2C7D3DC0C077254E51012DC09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6NK	01030000A034BF0D00010000000B000000208CD6DFB0EF35C0F048786D4BDE2BC09A9999999999E93F607246EE96B035C0F048786D4BDE2BC09A9999999999E93F607246EE96B035C0287CABA07E112DC09A9999999999E93F208CD6DFB0EF35C0287CABA07E112DC09A9999999999E93F208CD6DFB0EF35C070BE8E41EFBD32C09A9999999999E93FD093F349FAD635C070BE8E41EFBD32C09A9999999999E93FD093F349FAD635C02CA074D5AADA32C09A9999999999E93F208CD6DFB06F32C02CA074D5AADA32C09A9999999999E93F208CD6DFB06F32C068550ABE186B28C09A9999999999E93F208CD6DFB0EF35C068550ABE186B28C09A9999999999E93F208CD6DFB0EF35C0F048786D4BDE2BC09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6NP	01030000A034BF0D00010000000B00000040E40F52C17A2EC0287CABA07E112DC09A9999999999E93F40E40F52C17A2EC0F048786D4BDE2BC09A9999999999E93F904D4EE510B32DC0F048786D4BDE2BC09A9999999999E93F904D4EE510B32DC068550ABE186B28C09A9999999999E93F88F23C46175632C068550ABE186B28C09A9999999999E93F88F23C46175632C02CA074D5AADA32C09A9999999999E93F30C547338CE02DC02CA074D5AADA32C09A9999999999E93F30C547338CE02DC024052914C6BD32C09A9999999999E93F904D4EE510B32DC024052914C6BD32C09A9999999999E93F904D4EE510B32DC0287CABA07E112DC09A9999999999E93F40E40F52C17A2EC0287CABA07E112DC09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6Ot	01030000A034BF0D00010000000B0000008A99892629EC4CC0686545C1E0E32BC09A9999999999E93F4AED406DFCC44CC0686545C1E0E32BC09A9999999999E93F4AED406DFCC44CC0A09878F413172DC09A9999999999E93F72DAB99F2AF34CC0A09878F413172DC09A9999999999E93F72DAB99F2AF34CC00429B924BDBE32C09A9999999999E93F1289468858EB4CC00429B924BDBE32C09A9999999999E93F1289468858EB4CC024D2B1DF81DE32C09A9999999999E93F12ABEF396A384BC024D2B1DF81DE32C09A9999999999E93F12ABEF396A384BC068550ABE186B28C09A9999999999E93F8A99892629EC4CC068550ABE186B28C09A9999999999E93F8A99892629EC4CC0686545C1E0E32BC09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6NV	01030000A034BF0D00010000000C0000002856DF73D4F035C0D057762BA64822C09A9999999999E93F680CDCB67AB035C0D057762BA64822C09A9999999999E93F680CDCB67AB035C0680F4036204A23C09A9999999999E93FA81A580E1A4731C0680F4036204A23C09A9999999999E93FA81A580E1A4731C020937474305613C09A9999999999E93FD0CE647C4E4F32C020937474305613C09A9999999999E93FA83BEC3AC56332C020937474305613C09A9999999999E93FA83BEC3AC56332C030FB22BC115113C09A9999999999E93F18B0DF90FCD635C030FB22BC115113C09A9999999999E93F18B0DF90FCD635C080432FD689C413C09A9999999999E93F2856DF73D4F035C080432FD689C413C09A9999999999E93F2856DF73D4F035C0D057762BA64822C09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6NC	01030000A034BF0D000100000009000000BC792B8E702B42C028CB08BE514922C09A9999999999E93FBC792B8E700B42C028CB08BE514922C09A9999999999E93FBC792B8E700B42C0680F4036204A23C09A9999999999E93F588452524AAF3FC0680F4036204A23C09A9999999999E93F588452524AAF3FC030FB22BC115113C09A9999999999E93F38D72A7BB11E42C030FB22BC115113C09A9999999999E93F38D72A7BB11E42C040DB96D3CFC513C09A9999999999E93FBC792B8E702B42C040DB96D3CFC513C09A9999999999E93FBC792B8E702B42C028CB08BE514922C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048fI	01030000A034BF0D00010000001300000051A9037F0A1650C030B03E8568001BC09A9999999999E93F51A9037F0A1650C068133305CC9422C09A9999999999E93FA2A11379631F4EC068133305CC9422C09A9999999999E93FA2A11379631F4EC0D0EEFB6B85611CC09A9999999999E93FA2A11379631F4EC0B080FF248F611AC09A9999999999E93F32FB207287324EC0B080FF248F611AC09A9999999999E93F32FB207287324EC0B080FF248F6119C09A9999999999E93F32FA53A5BA354EC0B080FF248F6119C09A9999999999E93F32FA53A5BA354EC050B9B5D2EB4715C09A9999999999E93F32FB207287324EC050B9B5D2EB4715C09A9999999999E93F32FB207287324EC030EA6191DF3D13C09A9999999999E93FA20F302A8DA24EC030EA6191DF3D13C09A9999999999E93F22E08D90F3284FC030EA6191DF3D13C09A9999999999E93F9AB0EBF659AF4FC030EA6191DF3D13C09A9999999999E93F51A9037F0A1650C030EA6191DF3D13C09A9999999999E93F51A9037F0A1650C070BA1529D93D1AC09A9999999999E93F5A6D1BDCACEE4EC070BA1529D93D1AC09A9999999999E93F5A6D1BDCACEE4EC030B03E8568001BC09A9999999999E93F51A9037F0A1650C030B03E8568001BC09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048kF	01030000A034BF0D0001000000140000008078F527AB7011C010473CE7B9421BC09A9999999999E93F8078F527AB7011C0500A65D97D9422C09A9999999999E93F0010C12DEE49CFBF500A65D97D9422C09A9999999999E93F0010C12DEE49CFBFF8554C4F5CCA21C09A9999999999E93F0010C12DEE49CFBFF04B3A66D0231CC09A9999999999E93F0010C12DEE49CFBF0014A9FB295C1AC09A9999999999E93F008ACA1DCE76DCBF0014A9FB295C1AC09A9999999999E93F008ACA1DCE76DCBF008AC19F9A9915C09A9999999999E93F001497A2CF95D9BF008AC19F9A9915C09A9999999999E93F001497A2CF95D9BF409498430BD714C09A9999999999E93F0088505BB6FDCFBF409498430BD714C09A9999999999E93F0088505BB6FDCFBF301739B28C5C13C09A9999999999E93F00864FEC40D6F3BF301739B28C5C13C09A9999999999E93FC0CA04DC865102C0301739B28C5C13C09A9999999999E93F40D2E141EDB70AC0301739B28C5C13C09A9999999999E93F8078F527AB7011C0301739B28C5C13C09A9999999999E93F8078F527AB7011C05051138B2A801AC09A9999999999E93F00C9B3771AC1FDBF5051138B2A801AC09A9999999999E93F00C9B3771AC1FDBF10473CE7B9421BC09A9999999999E93F8078F527AB7011C010473CE7B9421BC09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048f3	01030000A034BF0D000100000012000000755CA765852252C0A07850A9EECA21C09A9999999999E93F755CA765852252C0809C9623A89C22C09A9999999999E93F896A378D2C1C51C0809C9623A89C22C09A9999999999E93F896A378D2C1C51C0A0523EB9D11A1BC09A9999999999E93F65DE8E3123BC51C0A0523EB9D11A1BC09A9999999999E93F65DE8E3123BC51C0E05C155D42581AC09A9999999999E93F896A378D2C1C51C0E05C155D42581AC09A9999999999E93F896A378D2C1C51C080F870FE635813C09A9999999999E93FF110F9E7D55B51C080F870FE635813C09A9999999999E93F2DF9271B099F51C080F870FE635813C09A9999999999E93F6DE1564E3CE251C080F870FE635813C09A9999999999E93FA9C0CB5D8B2252C080F870FE635813C09A9999999999E93FA9C0CB5D8B2252C0A09C5720AAE214C09A9999999999E93FC5B2259ABE1552C0A09C5720AAE214C09A9999999999E93FC5B2259ABE1552C0509823933A7C1AC09A9999999999E93F755CA765852252C0509823933A7C1AC09A9999999999E93F755CA765852252C0E06D57D8C8671CC09A9999999999E93F755CA765852252C0A07850A9EECA21C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048kj	01030000A034BF0D000100000013000000F05DA33F68DE20C0A833435BDB9422C09A9999999999E93FF05DA33F68DE20C0806036B7B6291BC09A9999999999E93F905F68FD89DE25C0806036B7B6291BC09A9999999999E93F905F68FD89DE25C0C06A0D5B27671AC09A9999999999E93FF05DA33F68DE20C0C06A0D5B27671AC09A9999999999E93FF05DA33F68DE20C0A086E9DC826713C09A9999999999E93F6064167ADCE822C0A086E9DC826713C09A9999999999E93F50773460860225C0A086E9DC826713C09A9999999999E93F30E804AD0F1C27C0A086E9DC826713C09A9999999999E93FA06942DA081229C0A086E9DC826713C09A9999999999E93FA06942DA081229C080FBB8E9939514C09A9999999999E93F309A05A659AB28C080FBB8E9939514C09A9999999999E93F309A05A659AB28C0E05F838CEBCD19C09A9999999999E93F406DC0E3AC1129C0E05F838CEBCD19C09A9999999999E93F406DC0E3AC1129C040325D3A1A2A1AC09A9999999999E93F406DC0E3AC1129C040325D3A1A2A1CC09A9999999999E93F406DC0E3AC1129C0E0ACFF4F40C821C09A9999999999E93F306B908F9B1129C0A833435BDB9422C09A9999999999E93FF05DA33F68DE20C0A833435BDB9422C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048hL	01030000A034BF0D00010000000800000039B139CCA72550C0F40CE4D129D234C09A9999999999E93F39B139CCA72550C078E02608E29E32C09A9999999999E93FFDE60179457F50C078E02608E29E32C09A9999999999E93FFDE60179457F50C0308D033138A42CC09A9999999999E93F39548F320E0C51C0308D033138A42CC09A9999999999E93F39548F320E0C51C08430F191E31033C09A9999999999E93F39548F320E0C51C0F40CE4D129D234C09A9999999999E93F39B139CCA72550C0F40CE4D129D234C09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6Nz	01030000A034BF0D0001000000090000006A001E78A55E49C048A5F296EF4922C09A9999999999E93F6A001E78A53E49C048A5F296EF4922C09A9999999999E93F6A001E78A53E49C0680F4036204A23C09A9999999999E93F7A1156A0D09E47C0680F4036204A23C09A9999999999E93F7A1156A0D09E47C030FB22BC115113C09A9999999999E93FDAEE8AF7E65149C030FB22BC115113C09A9999999999E93FDAEE8AF7E65149C0301D87AD1CC713C09A9999999999E93F6A001E78A55E49C0301D87AD1CC713C09A9999999999E93F6A001E78A55E49C048A5F296EF4922C09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6Nu	01030000A034BF0D000100000009000000080057F4D6F145C0680F4036204A23C09A9999999999E93F080057F4D6F145C0E891133C9D4922C09A9999999999E93F1C8293AAA7D245C0E891133C9D4922C09A9999999999E93F1C8293AAA7D245C0E0FAC8F777C613C09A9999999999E93FC09B92C4B3DE45C0E0FAC8F777C613C09A9999999999E93FC09B92C4B3DE45C030FB22BC115113C09A9999999999E93FAA4489D3039247C030FB22BC115113C09A9999999999E93FAA4489D3039247C0680F4036204A23C09A9999999999E93F080057F4D6F145C0680F4036204A23C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048kp	01030000A034BF0D00010000000E0000000080B7521926DABF50626F0D006033C09A9999999999E93F0080B7521926DABF50626F0D00E032C09A9999999999E93F00E846B25A8AD0BF50626F0D00E032C09A9999999999E93F00E846B25A8AD0BF988677D39BD931C09A9999999999E93F009E826AE2DFD8BF988677D39BD931C09A9999999999E93F009E826AE2DFD8BF645344A068A631C09A9999999999E93F00FCAB9CD78ECEBF645344A068A631C09A9999999999E93F00FCAB9CD78ECEBFFC302EA7991931C09A9999999999E93F00FCAB9CD78ECEBFBC04EF4B2D0E31C09A9999999999E93F404EBBD74E5A11C0BC04EF4B2D0E31C09A9999999999E93F404EBBD74E5A11C07C3C6A7F140035C09A9999999999E93F00E846B25A8AD0BF7C3C6A7F140035C09A9999999999E93F00E846B25A8AD0BF50626F0D006033C09A9999999999E93F0080B7521926DABF50626F0D006033C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048f9	01030000A034BF0D00010000000D0000009AA0AEC5EE344EC0747176ECFA5133C09A9999999999E93F02377E00BD314EC0747176ECFA5133C09A9999999999E93F02377E00BD314EC0747176ECFAD132C09A9999999999E93F6A2EAB61AB334EC0747176ECFAD132C09A9999999999E93F6A2EAB61AB334EC058D846CFFA9131C09A9999999999E93F72B89C2B971E4EC058D846CFFA9131C09A9999999999E93F72B89C2B971E4EC07CF2F728E80331C09A9999999999E93FA1C234FCB11550C07CF2F728E80331C09A9999999999E93F39B139CCA71550C0FC9A580047E534C09A9999999999E93FD2553D83853E4EC0381997FB30E534C09A9999999999E93FD2553D83853E4EC0CC8D56ECFA5134C09A9999999999E93F9AA0AEC5EE344EC0CC8D56ECFA5134C09A9999999999E93F9AA0AEC5EE344EC0747176ECFA5133C09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6Na	01030000A034BF0D00010000000A000000F2C15239C4FC4CC098A97F17474A22C09A9999999999E93F0AE5F51F0BC54CC098A97F17474A22C09A9999999999E93F0AE5F51F0BC54CC0680F4036204A23C09A9999999999E93F2A59371BE5CC4BC0680F4036204A23C09A9999999999E93F2A59371BE5CC4BC0706B396A593213C09A9999999999E93FBA1CEC9080EB4CC0706B396A593213C09A9999999999E93FBA1CEC9080EB4CC0704FD1F4BDC713C09A9999999999E93FF2C15239C4FC4CC0704FD1F4BDC713C09A9999999999E93FF2C15239C4FC4CC00015E8FE66611AC09A9999999999E93FF2C15239C4FC4CC098A97F17474A22C09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6N_	01030000A034BF0D0001000000090000003ACDEA44728B49C0680F4036204A23C09A9999999999E93F3ACDEA44728B49C048A5F296EF4922C09A9999999999E93F3ACDEA44726B49C048A5F296EF4922C09A9999999999E93F3ACDEA44726B49C0301D87AD1CC713C09A9999999999E93F4255F15D4D7849C0301D87AD1CC713C09A9999999999E93F4255F15D4D7849C0706B396A593213C09A9999999999E93F828C3FC701974AC0706B396A593213C09A9999999999E93F828C3FC701974AC0680F4036204A23C09A9999999999E93F3ACDEA44728B49C0680F4036204A23C09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6Nt	01030000A034BF0D00010000000B00000050B5C6DDDAC545C0E891133C9D4922C09A9999999999E93F3C338A270AA545C0E891133C9D4922C09A9999999999E93F3C338A270AA545C0680F4036204A23C09A9999999999E93FF42504E8B19944C0680F4036204A23C09A9999999999E93FF42504E8B19944C030FB22BC115113C09A9999999999E93FC06F2EBC671D45C030FB22BC115113C09A9999999999E93FC06F2EBC671D45C040CB7F4BD44613C09A9999999999E93F5C352C5E4DB845C040CB7F4BD44613C09A9999999999E93F5C352C5E4DB845C0E0FAC8F777C613C09A9999999999E93F50B5C6DDDAC545C0E0FAC8F777C613C09A9999999999E93F50B5C6DDDAC545C0E891133C9D4922C09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6NB	01030000A034BF0D00010000000A000000483F9DF14A7D3DC0680F4036204A23C09A9999999999E93F483F9DF14A7D3DC0D0B72963FF4822C09A9999999999E93FF022AC40A13D3DC0D0B72963FF4822C09A9999999999E93FF022AC40A13D3DC000C064AF27C513C09A9999999999E93F40086590FC563DC000C064AF27C513C09A9999999999E93F40086590FC563DC020937474305613C09A9999999999E93F00714B1FBF8C3FC020937474305613C09A9999999999E93FD8EBB8B8B0953FC020937474305613C09A9999999999E93FD8EBB8B8B0953FC0680F4036204A23C09A9999999999E93F483F9DF14A7D3DC0680F4036204A23C09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6N6	01030000A034BF0D000100000009000000588912A707243DC0D0B72963FF4822C09A9999999999E93FB0A50358B1E33CC0D0B72963FF4822C09A9999999999E93FB0A50358B1E33CC0680F4036204A23C09A9999999999E93FE8C6C444F7CB3AC0680F4036204A23C09A9999999999E93FE8C6C444F7CB3AC020937474305613C09A9999999999E93F703B98C32F0A3DC020937474305613C09A9999999999E93F703B98C32F0A3DC000C064AF27C513C09A9999999999E93F588912A707243DC000C064AF27C513C09A9999999999E93F588912A707243DC0D0B72963FF4822C09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6Nn	01030000A034BF0D0001000000090000008846F85A3D5842C0680F4036204A23C09A9999999999E93F8846F85A3D5842C028CB08BE514922C09A9999999999E93F8846F85A3D3842C028CB08BE514922C09A9999999999E93F8846F85A3D3842C040DB96D3CFC513C09A9999999999E93F9C3D91E1174542C040DB96D3CFC513C09A9999999999E93F9C3D91E1174542C020937474305613C09A9999999999E93F64F8FE54EF6343C020937474305613C09A9999999999E93F64F8FE54EF6343C0680F4036204A23C09A9999999999E93F8846F85A3D5842C0680F4036204A23C09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6N0	01030000A034BF0D00010000000900000000A67550144A36C0680F4036204A23C09A9999999999E93F00A67550144A36C0D057762BA64822C09A9999999999E93FC0EF780D6E0A36C0D057762BA64822C09A9999999999E93FC0EF780D6E0A36C080432FD689C413C09A9999999999E93FE87CAC5DC92336C080432FD689C413C09A9999999999E93FE87CAC5DC92336C020937474305613C09A9999999999E93F9893E94A786138C020937474305613C09A9999999999E93F9893E94A786138C0680F4036204A23C09A9999999999E93F00A67550144A36C0680F4036204A23C09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6NQ	01030000A034BF0D00010000000A00000090950CE5957A2EC0680F4036204A23C09A9999999999E93F90950CE5957A2EC0B83ED187554822C09A9999999999E93FE00946FE81B02DC0B83ED187554822C09A9999999999E93FE00946FE81B02DC0E0D47EF7372A1CC09A9999999999E93FE00946FE81B02DC070DA9843DEC313C09A9999999999E93F5042D4552CE12DC070DA9843DEC313C09A9999999999E93F5042D4552CE12DC020937474305613C09A9999999999E93F1081BE74802D31C020937474305613C09A9999999999E93F1081BE74802D31C0680F4036204A23C09A9999999999E93F90950CE5957A2EC0680F4036204A23C09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6NZ	01030000A034BF0D0001000000050000006A8C6A4E18C04BC0906C396A593213C09A9999999999E93F6A8C6A4E18C04BC0D80E4036204A23C09A9999999999E93F42590C94CEA34AC0D80E4036204A23C09A9999999999E93F42590C94CEA34AC0906C396A593213C09A9999999999E93F6A8C6A4E18C04BC0906C396A593213C09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6No	01030000A034BF0D00010000000700000030C5CB21BC7043C0680F4036204A23C09A9999999999E93F30C5CB21BC7043C020937474305613C09A9999999999E93F788EB3A7B9F543C020937474305613C09A9999999999E93F788EB3A7B9F543C030FB22BC115113C09A9999999999E93F2859371BE58C44C030FB22BC115113C09A9999999999E93F2859371BE58C44C0680F4036204A23C09A9999999999E93F30C5CB21BC7043C0680F4036204A23C09A9999999999E93F
first_floor	1BUg4a4jr0B9Q5NnDgB6N5	01030000A034BF0D000100000005000000D82C2BAB5DB23AC0B0917474305613C09A9999999999E93FD82C2BAB5DB23AC0F80D4036204A23C09A9999999999E93F882C83E4117B38C0F80D4036204A23C09A9999999999E93F882C83E4117B38C0B0917474305613C09A9999999999E93FD82C2BAB5DB23AC0B0917474305613C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048kT	01030000A034BF0D000100000007000000F05DA33F68DE20C0A0E046B84ECE02C09A9999999999E93FF05DA33F68DE20C00060CB53C288CDBF9A9999999999E93FA06942DA081229C00060CB53C288CDBF9A9999999999E93FA06942DA081229C0803AACF1480202C09A9999999999E93FE088EE88E2D128C0803AACF1480202C09A9999999999E93FE088EE88E2D128C0A0E046B84ECE02C09A9999999999E93FF05DA33F68DE20C0A0E046B84ECE02C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048kU	01030000A034BF0D00010000000500000000E4FFFFFFFFCFBF00CCE64694CD02C09A9999999999E93F00E4FFFFFFFFCFBF002C00000000D0BF9A9999999999E93F6079F527AB7011C0002C00000000D0BF9A9999999999E93F6079F527AB7011C000CCE64694CD02C09A9999999999E93F00E4FFFFFFFFCFBF00CCE64694CD02C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048k8	01030000A034BF0D00010000000A000000F05DA33F68DE20C0C099A290244937C09A9999999999E93FF05DA33F68DE20C0FC6CBB21A11A37C09A9999999999E93FF05DA33F68DE20C0846DACB4C13435C09A9999999999E93F4080F1E91F1129C0846DACB4C13435C09A9999999999E93F4080F1E91F1129C0C822E09DF14737C09A9999999999E93F4080F1E91F9128C0C822E09DF14737C09A9999999999E93F4080F1E91F9128C0D455E776FE4C37C09A9999999999E93FF0A1A28ED95D21C0D455E776FE4C37C09A9999999999E93FF0A1A28ED95D21C0C099A290244937C09A9999999999E93FF05DA33F68DE20C0C099A290244937C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048ks	01030000A034BF0D000100000009000000404EBBD74E5A11C0145118C7F53A35C09A9999999999E93F404EBBD74E5A11C0486A0E377F4637C09A9999999999E93F604FB3DD6A5A10C0486A0E377F4637C09A9999999999E93F604FB3DD6A5A10C0C87436A8704F37C09A9999999999E93F007423592D45E0BFC87436A8704F37C09A9999999999E93F007423592D45E0BF8CDDF558244537C09A9999999999E93F00E846B25A8AD0BF8CDDF558244537C09A9999999999E93F00E846B25A8AD0BF145118C7F53A35C09A9999999999E93F404EBBD74E5A11C0145118C7F53A35C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048kr	01030000A034BF0D0001000000070000008080684564C428C068655E3C302033C09A9999999999E93F8080684564C428C0A019216DE05933C09A9999999999E93F4080F1E91F1129C0A019216DE05933C09A9999999999E93F4080F1E91F1129C00859FE6CE0F934C09A9999999999E93FF05DA33F68DE20C00859FE6CE0F934C09A9999999999E93FF05DA33F68DE20C068655E3C302033C09A9999999999E93F8080684564C428C068655E3C302033C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048fC	01030000A034BF0D00010000000A00000025690C80DE1852C07082A9B0681C33C09A9999999999E93F25690C80DE1852C0D47D30D7415233C09A9999999999E93F959FEC43F21652C0D47D30D7415233C09A9999999999E93F959FEC43F21652C0B899BA20445234C09A9999999999E93F39F7E498741252C0B899BA20445234C09A9999999999E93F39F7E498741252C000AD1B735EE534C09A9999999999E93F39548F320E2C51C000AD1B735EE534C09A9999999999E93F39548F320E1C51C000AD1B735EE534C09A9999999999E93F39548F320E1C51C07082A9B0681C33C09A9999999999E93F25690C80DE1852C07082A9B0681C33C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048kv	01030000A034BF0D00010000000500000080C1A53CD2D122C0A0D4C58B46B00AC09A9999999999E93F80C1A53CD2D122C0F0F826E7590B13C09A9999999999E93F405FA33F68DE20C0F0F826E7590B13C09A9999999999E93F405FA33F68DE20C0A0D4C58B46B00AC09A9999999999E93F80C1A53CD2D122C0A0D4C58B46B00AC09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048k2	01030000A034BF0D000100000005000000C060A43716140BC0208876BC630013C09A9999999999E93FC060A43716140BC000616977349A0AC09A9999999999E93FE078F527AB7011C000616977349A0AC09A9999999999E93FE078F527AB7011C0208876BC630013C09A9999999999E93FC060A43716140BC0208876BC630013C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048kk	01030000A034BF0D000100000005000000B2E6D39ACA9C4EC000C5D9A6D78F0AC09A9999999999E93FB2E6D39ACA9C4EC040599F9BB6E112C09A9999999999E93F9AA11379631F4EC040599F9BB6E112C09A9999999999E93F9AA11379631F4EC000C5D9A6D78F0AC09A9999999999E93FB2E6D39ACA9C4EC000C5D9A6D78F0AC09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048kw	01030000A034BF0D000100000005000000500787B7E6FF22C0A0D4C58B46B00AC09A9999999999E93F30D2C3227CEB24C0A0D4C58B46B00AC09A9999999999E93F30D2C3227CEB24C0F0F826E7590B13C09A9999999999E93F500787B7E6FF22C0F0F826E7590B13C09A9999999999E93F500787B7E6FF22C0A0D4C58B46B00AC09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048k4	01030000A034BF0D000100000005000000C03A42E65DF501C0208876BC630013C09A9999999999E93F80A6D4D7928EF4BF208876BC630013C09A9999999999E93F80A6D4D7928EF4BF00616977349A0AC09A9999999999E93FC03A42E65DF501C000616977349A0AC09A9999999999E93FC03A42E65DF501C0208876BC630013C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048k1	01030000A034BF0D00010000000500000040421F4CC45B0AC0208876BC630013C09A9999999999E93FC05AC7D1AFAD02C0208876BC630013C09A9999999999E93FC05AC7D1AFAD02C000616977349A0AC09A9999999999E93F40421F4CC45B0AC000616977349A0AC09A9999999999E93F40421F4CC45B0AC0208876BC630013C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048kd	01030000A034BF0D000100000005000000201AA59D901925C0A0D4C58B46B00AC09A9999999999E93F2043946F050527C0A0D4C58B46B00AC09A9999999999E93F2043946F050527C0F0F826E7590B13C09A9999999999E93F201AA59D901925C0F0F826E7590B13C09A9999999999E93F201AA59D901925C0A0D4C58B46B00AC09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048kR	01030000A034BF0D000100000005000000006ACA00EF1DF3BF208876BC630013C09A9999999999E93F0070505BB6FDCFBF208876BC630013C09A9999999999E93F0070505BB6FDCFBF00616977349A0AC09A9999999999E93F006ACA00EF1DF3BF00616977349A0AC09A9999999999E93F006ACA00EF1DF3BF208876BC630013C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048fO	01030000A034BF0D000100000005000000B1E479D3279C51C0D06BAE083BFC12C09A9999999999E93F7125A72FB75E51C0D06BAE083BFC12C09A9999999999E93F7125A72FB75E51C0A01D6F3B8DC40AC09A9999999999E93FB1E479D3279C51C0A01D6F3B8DC40AC09A9999999999E93FB1E479D3279C51C0D06BAE083BFC12C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048f5	01030000A034BF0D000100000005000000EDCCA8065BDF51C0D06BAE083BFC12C09A9999999999E93FB10DD662EAA151C0D06BAE083BFC12C09A9999999999E93FB10DD662EAA151C0A01D6F3B8DC40AC09A9999999999E93FEDCCA8065BDF51C0A01D6F3B8DC40AC09A9999999999E93FEDCCA8065BDF51C0D06BAE083BFC12C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048fK	01030000A034BF0D0001000000050000001A09EA1FB62E4FC000C5D9A6D78F0AC09A9999999999E93FA2878F6797A94FC000C5D9A6D78F0AC09A9999999999E93FA2878F6797A94FC040599F9BB6E112C09A9999999999E93F1A09EA1FB62E4FC040599F9BB6E112C09A9999999999E93F1A09EA1FB62E4FC000C5D9A6D78F0AC09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048kh	01030000A034BF0D000100000005000000AA388CB94FA84EC000C5D9A6D78F0AC09A9999999999E93F22B7310131234FC000C5D9A6D78F0AC09A9999999999E93F22B7310131234FC040599F9BB6E112C09A9999999999E93FAA388CB94FA84EC040599F9BB6E112C09A9999999999E93FAA388CB94FA84EC000C5D9A6D78F0AC09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048f6	01030000A034BF0D000100000005000000A9C0CB5D8B2252C06095D54154C50AC09A9999999999E93FA9C0CB5D8B2252C02069AE083BFC12C09A9999999999E93FE5F504961DE551C02069AE083BFC12C09A9999999999E93FE5F504961DE551C0401A6F3B8DC40AC09A9999999999E93FA9C0CB5D8B2252C06095D54154C50AC09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048kW	01030000A034BF0D000100000007000000A06942DA081229C050F726E7590B13C09A9999999999E93F008C75EA193327C050F726E7590B13C09A9999999999E93F008C75EA193327C0E0D7C58B46B00AC09A9999999999E93FE088EE88E2D128C0E0D7C58B46B00AC09A9999999999E93FE088EE88E2D128C0A067AFDDFECE0AC09A9999999999E93FA06942DA081229C0A067AFDDFECE0AC09A9999999999E93FA06942DA081229C050F726E7590B13C09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048fV	01030000A034BF0D00010000000500000069FC4AA0F45851C0A01D6F3B8DC40AC09A9999999999E93F69FC4AA0F45851C0D06BAE083BFC12C09A9999999999E93F556A378D2C1C51C0D06BAE083BFC12C09A9999999999E93F556A378D2C1C51C0A01D6F3B8DC40AC09A9999999999E93F69FC4AA0F45851C0A01D6F3B8DC40AC09A9999999999E93F
first_floor	1mWTVVwiXDHQKYjSZ048fH	01030000A034BF0D00010000000500000072D947861CB54FC040599F9BB6E112C09A9999999999E93F72D947861CB54FC000C5D9A6D78F0AC09A9999999999E93F61A9037F0A1650C000C5D9A6D78F0AC09A9999999999E93F61A9037F0A1650C040599F9BB6E112C09A9999999999E93F72D947861CB54FC040599F9BB6E112C09A9999999999E93F
second_floor	1mWTVVwiXDHQKYjSZ04A3D	01030000A034BF0D0001000000400000000010C12DEE49CFBF30857987C5F522C000000000000008408078F527AB7012C030857987C5F522C000000000000008408078F527AB7012C00000A561EDB9933F0000000000000840F05DA33F685E20C00000A561EDB9933F0000000000000840F05DA33F685E20C000CF256ED1FF22C000000000000008403091D6729B9129C000CF256ED1FF22C000000000000008403091D6729B9129C0009E4BDCA2FF1BC00000000000000840B078EBB99CC92CC0009E4BDCA2FF1BC00000000000000840B078EBB99CC92CC0680A704B120E23C0000000000000084010DF512003302CC0680A704B120E23C0000000000000084010DF512003302CC0A03A7185218023C000000000000008405A4FB8383E564DC0A03A7185218023C000000000000008405A4FB8383E564DC0C818DF80EBFA22C00000000000000840F214B94798304DC0C818DF80EBFA22C00000000000000840F214B94798304DC00015E8FE66611CC0000000000000084082D7AE70F4FF4DC00015E8FE66611CC0000000000000084082D7AE70F4FF4DC048009DDB42F322C0000000000000084051A9037F0A2650C048009DDB42F322C0000000000000084051A9037F0A2650C060CD068452B31AC00000000000000840E1AB77E1840A51C060CD068452B31AC00000000000000840E1AB77E1840A51C0A0D26601810323C00000000000000840755CA765853252C0A0D26601810323C00000000000000840755CA765853252C0E06D57D8C8671CC00000000000000840C5030026419152C0E06D57D8C8671CC00000000000000840C5030026419152C0C842B80212F922C00000000000000840BD3BF841548652C0C842B80212F922C00000000000000840BD3BF841548652C0980F85CFDEC528C00000000000000840C9129CB2919052C0980F85CFDEC528C00000000000000840C9129CB2919052C0FCBAF59A229630C00000000000000840C9129CB2913052C0FCBAF59A229630C00000000000000840C9129CB2913052C090D498BCE3472CC0000000000000084061870CE28F2252C090D498BCE3472CC0000000000000084061870CE28F2252C088FDF44BA63D2DC00000000000000840811496C7671D51C088FDF44BA63D2DC00000000000000840811496C7671D51C0A882E09D5E5C2CC00000000000000840AA996999A61E4EC0A882E09D5E5C2CC00000000000000840AA996999A61E4EC090D498BCE34728C000000000000008404233033340F84CC090D498BCE34728C000000000000008404233033340F84CC03014EA9F4C2E28C0000000000000084072663666732B4BC03014EA9F4C2E28C0000000000000084072663666732B4BC0E8326F8B9EE62BC000000000000008403C077FFC5FD145C0E8326F8B9EE62BC000000000000008403C077FFC5FD145C01866A2BED11928C00000000000000840780EFEF8BF223DC01866A2BED11928C00000000000000840780EFEF8BF223DC0C8AD8339E6C72BC0000000000000084048DBCAC58C6F32C0C8AD8339E6C72BC0000000000000084048DBCAC58C6F32C01866A2BED11928C00000000000000840D09710A0C7262DC01866A2BED11928C00000000000000840D09710A0C7262DC040C23181C74228C00000000000000840D09710A0C72629C040C23181C74228C00000000000000840D09710A0C72629C0108FFE4D940F2DC00000000000000840D0B050E561EA20C0108FFE4D940F2DC00000000000000840D0B050E561EA20C0B00C467B70462CC0000000000000084020764F12A54F12C0B00C467B70462CC0000000000000084020764F12A54F12C0C8BA8D5CEB5A2CC0000000000000084000D89C91836FCEBFC8BA8D5CEB5A2CC0000000000000084000D89C91836FCEBF80D912483D1329C00000000000000840008E281DD227F53F80D912483D1329C00000000000000840008E281DD227F53F387CEC74B3F522C00000000000000840006ED2D5D70BF93F387CEC74B3F522C00000000000000840006ED2D5D70BF93F8043C6B8B8231CC000000000000008400000DE473AC2763F8043C6B8B8231CC000000000000008400000DE473AC2763F30857987C5F522C000000000000008400010C12DEE49CFBF30857987C5F522C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048lQ	01030000A034BF0D0001000000130000000080B7521926DABF50626F0D006033C000000000000008400080B7521926DABF50626F0D00E032C0000000000000084000E846B25A8AD0BF50626F0D00E032C0000000000000084000E846B25A8AD0BF988677D39BD931C00000000000000840009E826AE2DFD8BF988677D39BD931C00000000000000840009E826AE2DFD8BF645344A068A631C0000000000000084000FCAB9CD78ECEBF645344A068A631C0000000000000084000FCAB9CD78ECEBFFC302EA7991931C0000000000000084000FCAB9CD78ECEBFFC302EA7999930C0000000000000084000FCAB9CD78ECEBF60D06649BBDE2CC00000000000000840404EBBD74E5A11C060D06649BBDE2CC00000000000000840404EBBD74E5A11C0486A0E377F4637C00000000000000840604FB3DD6A5A10C0486A0E377F4637C00000000000000840604FB3DD6A5A10C0C87436A8704F37C00000000000000840007423592D45E0BFC87436A8704F37C00000000000000840007423592D45E0BF8CDDF558244537C0000000000000084000E846B25A8AD0BF8CDDF558244537C0000000000000084000E846B25A8AD0BF50626F0D006033C000000000000008400080B7521926DABF50626F0D006033C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048lD	01030000A034BF0D000100000005000000105FA33F685E20C0409C1657F7752CC00000000000000840105FA33F685E20C0A881F5AD091B37C000000000000008406050BBD74E5A12C0A881F5AD091B37C000000000000008406050BBD74E5A12C0409C1657F7752CC00000000000000840105FA33F685E20C0409C1657F7752CC00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048lf	01030000A034BF0D00010000000D0000009AA0AEC5EE344EC0747176ECFA5133C0000000000000084002377E00BD314EC0747176ECFA5133C0000000000000084002377E00BD314EC0747176ECFAD132C000000000000008406A2EAB61AB334EC0747176ECFAD132C000000000000008406A2EAB61AB334EC058D846CFFA9131C0000000000000084072B89C2B971E4EC058D846CFFA9131C0000000000000084072B89C2B971E4EC0E849C9C798C22CC00000000000000840A1C234FCB11550C0E849C9C798C22CC0000000000000084039B139CCA71550C0FC9A580047E534C00000000000000840D2553D83853E4EC0381997FB30E534C00000000000000840D2553D83853E4EC0CC8D56ECFA5134C000000000000008409AA0AEC5EE344EC0CC8D56ECFA5134C000000000000008409AA0AEC5EE344EC0747176ECFA5133C00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6MV	01030000A034BF0D00010000000B000000B81B2D44412C42C0C8031957EBE22BC00000000000000840DCC550217D0B42C0C8031957EBE22BC00000000000000840DCC550217D0B42C0F8364C8A1E162DC000000000000008404C035BF8202C42C0F8364C8A1E162DC000000000000008404C035BF8202C42C02CA2779C41BE32C00000000000000840C8A452BB871E42C02CA2779C41BE32C00000000000000840C8A452BB871E42C00C6B9D313ADD32C00000000000000840084FE576356A40C0286C9D313ADD32C00000000000000840084FE576356A40C0D0BB70247F5128C00000000000000840B81B2D44412C42C0D0BB70247F5128C00000000000000840B81B2D44412C42C0C8031957EBE22BC00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6MQ	01030000A034BF0D00010000000B000000A8921DEE495842C0F8364C8A1E162DC00000000000000840A8921DEE495842C0C8031957EBE22BC00000000000000840A46DE562C63742C0C8031957EBE22BC00000000000000840A46DE562C63742C0D0BB70247F5128C0000000000000084084E8F9100EF943C0D0BB70247F5128C0000000000000084084E8F9100EF943C024D2B1DF81DE32C00000000000000840300BB921EE4442C024D2B1DF81DE32C00000000000000840300BB921EE4442C02CA2779C41BE32C0000000000000084038551317A63742C02CA2779C41BE32C0000000000000084038551317A63742C0F8364C8A1E162DC00000000000000840A8921DEE495842C0F8364C8A1E162DC00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6MP	01030000A034BF0D00010000000B00000050B5C6DDDAC545C09878E4B13DE32BC00000000000000840AC5ABA6DFCA445C09878E4B13DE32BC00000000000000840AC5ABA6DFCA445C0C8AB17E570162DC000000000000008401C98C444A0C545C0C8AB17E570162DC000000000000008401C98C444A0C545C0DC2BE7C96ABE32C00000000000000840E4898B5525B845C0DC2BE7C96ABE32C00000000000000840E4898B5525B845C024D2B1DF81DE32C00000000000000840703AB22F930444C024D2B1DF81DE32C00000000000000840703AB22F930444C0D0BB70247F5128C0000000000000084050B5C6DDDAC545C0D0BB70247F5128C0000000000000084050B5C6DDDAC545C09878E4B13DE32BC00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6M0	01030000A034BF0D00010000000B0000009098890F2C7D3DC0C077254E51012DC000000000000008409098890F2C7D3DC08844F21A1ECE2BC000000000000008404856D4771B3C3DC08844F21A1ECE2BC000000000000008404856D4771B3C3DC0D0BB70247F5128C000000000000008401CFD2C58B05E40C0D0BB70247F5128C000000000000008401CFD2C58B05E40C0286C9D313ADD32C0000000000000084080F96812B1563DC0286C9D313ADD32C0000000000000084080F96812B1563DC08018086F18BE32C00000000000000840B01D7561E43B3DC08018086F18BE32C00000000000000840B01D7561E43B3DC0C077254E51012DC000000000000008409098890F2C7D3DC0C077254E51012DC00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048kN	01030000A034BF0D00010000000500000039B139CCA72550C0F40CE4D129D234C00000000000000840A1C234FCB12550C08842CD9CEABD2CC0000000000000084039548F320E0C51C08842CD9CEABD2CC0000000000000084039548F320E0C51C0F40CE4D129D234C0000000000000084039B139CCA72550C0F40CE4D129D234C00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6MC	01030000A034BF0D00010000000C00000040E40F52C17A2EC0287CABA07E112DC0000000000000084040E40F52C17A2EC0F048786D4BDE2BC00000000000000840904D4EE510B32DC0F048786D4BDE2BC00000000000000840904D4EE510B32DC0D0BB70247F5128C00000000000000840686D51F45E5732C0D0BB70247F5128C00000000000000840686D51F45E5732C0C8F3256190EA2BC00000000000000840686D51F45E5732C02CA074D5AADA32C0000000000000084030C547338CE02DC02CA074D5AADA32C0000000000000084030C547338CE02DC024052914C6BD32C00000000000000840904D4EE510B32DC024052914C6BD32C00000000000000840904D4EE510B32DC0287CABA07E112DC0000000000000084040E40F52C17A2EC0287CABA07E112DC00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6Ng	01030000A034BF0D00010000000C0000008A99892629EC4CC0686545C1E0E32BC000000000000008404AED406DFCC44CC0686545C1E0E32BC000000000000008404AED406DFCC44CC0A09878F413172DC0000000000000084072DAB99F2AF34CC0A09878F413172DC0000000000000084072DAB99F2AF34CC00429B924BDBE32C000000000000008401289468858EB4CC00429B924BDBE32C000000000000008401289468858EB4CC024D2B1DF81DE32C00000000000000840A26DE562C6374BC024D2B1DF81DE32C00000000000000840A26DE562C6374BC030127E4BD7FC2BC00000000000000840A26DE562C6374BC07846AB03CF5E28C000000000000008408A99892629EC4CC07846AB03CF5E28C000000000000008408A99892629EC4CC0686545C1E0E32BC00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048l$	01030000A034BF0D00010000001300000051A9037F0A1650C030B03E8568001BC0000000000000084051A9037F0A1650C068133305CC9422C00000000000000840A2A11379631F4EC068133305CC9422C00000000000000840A2A11379631F4EC0D0EEFB6B85611CC00000000000000840A2A11379631F4EC0B080FF248F611AC0000000000000084032FB207287324EC0B080FF248F611AC0000000000000084032FB207287324EC0B080FF248F6119C0000000000000084032FA53A5BA354EC0B080FF248F6119C0000000000000084032FA53A5BA354EC050B9B5D2EB4715C0000000000000084032FB207287324EC050B9B5D2EB4715C0000000000000084032FB207287324EC030EA6191DF3D13C00000000000000840A20F302A8DA24EC030EA6191DF3D13C0000000000000084022E08D90F3284FC030EA6191DF3D13C000000000000008409AB0EBF659AF4FC030EA6191DF3D13C0000000000000084051A9037F0A1650C030EA6191DF3D13C0000000000000084051A9037F0A1650C070BA1529D93D1AC000000000000008405A6D1BDCACEE4EC070BA1529D93D1AC000000000000008405A6D1BDCACEE4EC030B03E8568001BC0000000000000084051A9037F0A1650C030B03E8568001BC00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048lP	01030000A034BF0D0001000000140000000010C12DEE49CFBF500A65D97D9422C000000000000008400010C12DEE49CFBFF8554C4F5CCA21C000000000000008400010C12DEE49CFBFF04B3A66D0231CC000000000000008400010C12DEE49CFBF0014A9FB295C1AC00000000000000840008ACA1DCE76DCBF0014A9FB295C1AC00000000000000840008ACA1DCE76DCBF008AC19F9A9915C00000000000000840001497A2CF95D9BF008AC19F9A9915C00000000000000840001497A2CF95D9BF409498430BD714C000000000000008400088505BB6FDCFBF409498430BD714C000000000000008400088505BB6FDCFBF301739B28C5C13C0000000000000084000864FEC40D6F3BF301739B28C5C13C00000000000000840C0CA04DC865102C0301739B28C5C13C0000000000000084040D2E141EDB70AC0301739B28C5C13C000000000000008408078F527AB7011C0301739B28C5C13C000000000000008408078F527AB7011C05051138B2A801AC0000000000000084000C9B3771AC1FDBF5051138B2A801AC0000000000000084000C9B3771AC1FDBF10473CE7B9421BC000000000000008408078F527AB7011C010473CE7B9421BC000000000000008408078F527AB7011C0500A65D97D9422C000000000000008400010C12DEE49CFBF500A65D97D9422C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048li	01030000A034BF0D000100000012000000755CA765852252C0A07850A9EECA21C00000000000000840755CA765852252C0809C9623A89C22C00000000000000840896A378D2C1C51C0809C9623A89C22C00000000000000840896A378D2C1C51C0A0523EB9D11A1BC0000000000000084065DE8E3123BC51C0A0523EB9D11A1BC0000000000000084065DE8E3123BC51C0E05C155D42581AC00000000000000840896A378D2C1C51C0E05C155D42581AC00000000000000840896A378D2C1C51C080F870FE635813C00000000000000840F110F9E7D55B51C080F870FE635813C000000000000008402DF9271B099F51C080F870FE635813C000000000000008406DE1564E3CE251C080F870FE635813C00000000000000840A9C0CB5D8B2252C080F870FE635813C00000000000000840A9C0CB5D8B2252C0A09C5720AAE214C00000000000000840C5B2259ABE1552C0A09C5720AAE214C00000000000000840C5B2259ABE1552C0509823933A7C1AC00000000000000840755CA765852252C0509823933A7C1AC00000000000000840755CA765852252C0E06D57D8C8671CC00000000000000840755CA765852252C0A07850A9EECA21C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048iY	01030000A034BF0D000100000013000000306B908F9B1129C0E0ACFF4F40C821C00000000000000840306B908F9B1129C0A833435BDB9422C00000000000000840F05DA33F68DE20C0A833435BDB9422C00000000000000840F05DA33F68DE20C0806036B7B6291BC00000000000000840905F68FD89DE25C0806036B7B6291BC00000000000000840905F68FD89DE25C0C06A0D5B27671AC00000000000000840F05DA33F68DE20C0C06A0D5B27671AC00000000000000840F05DA33F68DE20C0A086E9DC826713C000000000000008406064167ADCE822C0A086E9DC826713C0000000000000084050773460860225C0A086E9DC826713C0000000000000084030E804AD0F1C27C0A086E9DC826713C00000000000000840A06942DA081229C0A086E9DC826713C00000000000000840A06942DA081229C080FBB8E9939514C00000000000000840309A05A659AB28C080FBB8E9939514C00000000000000840309A05A659AB28C0E05F838CEBCD19C00000000000000840406DC0E3AC1129C0E05F838CEBCD19C00000000000000840406DC0E3AC1129C040325D3A1A2A1AC00000000000000840406DC0E3AC1129C040325D3A1A2A1CC00000000000000840306B908F9B1129C0E0ACFF4F40C821C00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6M6	01030000A034BF0D000100000009000000F80BE087304A36C0287CABA07E112DC00000000000000840F80BE087304A36C0608DBFFA29042CC0000000000000084090B32F605C8B39C0608DBFFA29042CC0000000000000084090B32F605C8B39C0286C9D313ADD32C00000000000000840A060C016C72336C0286C9D313ADD32C00000000000000840A060C016C72336C070BE8E41EFBD32C00000000000000840D8AA5BCB020836C070BE8E41EFBD32C00000000000000840D8AA5BCB020836C0287CABA07E112DC00000000000000840F80BE087304A36C0287CABA07E112DC00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6M5	01030000A034BF0D000100000009000000F8FEEF7592E33CC0608DBFFA29042CC00000000000000840F8FEEF7592E33CC0C077254E51012DC00000000000000840D8790424DA243DC0C077254E51012DC00000000000000840D8790424DA243DC08018086F18BE32C00000000000000840B82C9C45E4093DC08018086F18BE32C00000000000000840B82C9C45E4093DC0286C9D313ADD32C000000000000008406057A09D66A239C0286C9D313ADD32C000000000000008406057A09D66A239C0608DBFFA29042CC00000000000000840F8FEEF7592E33CC0608DBFFA29042CC00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6MB	01030000A034BF0D000100000009000000607246EE96B035C0608DBFFA29042CC00000000000000840607246EE96B035C0287CABA07E112DC000000000000008400007EB8DF8F035C0287CABA07E112DC000000000000008400007EB8DF8F035C070BE8E41EFBD32C00000000000000840D093F349FAD635C070BE8E41EFBD32C00000000000000840D093F349FAD635C02CA074D5AADA32C000000000000008404011C231696E32C02CA074D5AADA32C000000000000008404011C231696E32C0608DBFFA29042CC00000000000000840607246EE96B035C0608DBFFA29042CC00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6MK	01030000A034BF0D0001000000090000007827873AC9F145C0C8AB17E570162DC000000000000008407827873AC9F145C0C8AB17E570162CC000000000000008401A8293AAA79247C0C8AB17E570162CC000000000000008401A8293AAA79247C024D2B1DF81DE32C000000000000008404CF0F1BB8BDE45C024D2B1DF81DE32C000000000000008404CF0F1BB8BDE45C0DC2BE7C96ABE32C0000000000000084008EA7C6325D145C0DC2BE7C96ABE32C0000000000000084008EA7C6325D145C0C8AB17E570162DC000000000000008407827873AC9F145C0C8AB17E570162DC00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6Nk	01030000A034BF0D000100000009000000AAF41A8B648B49C088722263BC162DC00000000000000840AAF41A8B648B49C0C8AB17E570162CC00000000000000840BA1B2D44412C4BC0C8AB17E570162CC00000000000000840BA1B2D44412C4BC024D2B1DF81DE32C00000000000000840CAA95055257849C024D2B1DF81DE32C00000000000000840CAA95055257849C08CB556F793BE32C000000000000008403AB710B4C06A49C08CB556F793BE32C000000000000008403AB710B4C06A49C088722263BC162DC00000000000000840AAF41A8B648B49C088722263BC162DC00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6MJ	01030000A034BF0D000100000009000000E2274EBE973E49C0C8AB17E570162CC00000000000000840E2274EBE973E49C088722263BC162DC00000000000000840526558953B5F49C088722263BC162DC00000000000000840526558953B5F49C08CB556F793BE32C000000000000008406243EAEEBE5149C08CB556F793BE32C000000000000008406243EAEEBE5149C024D2B1DF81DE32C000000000000008400AD44BC92C9E47C024D2B1DF81DE32C000000000000008400AD44BC92C9E47C0C8AB17E570162CC00000000000000840E2274EBE973E49C0C8AB17E570162CC00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6Mg	01030000A034BF0D00010000000B000000AC7094FEADC545C0E891133C9D4922C000000000000008403C338A270AA545C0E891133C9D4922C000000000000008403C338A270AA545C058FCC28A664523C0000000000000084068B8DD2D930444C058FCC28A664523C0000000000000084068B8DD2D930444C030FB22BC115113C00000000000000840C06F2EBC671D45C030FB22BC115113C00000000000000840C06F2EBC671D45C040CB7F4BD44613C000000000000008405C352C5E4DB845C040CB7F4BD44613C000000000000008405C352C5E4DB845C0E0FAC8F777C613C00000000000000840AC7094FEADC545C0E0FAC8F777C613C00000000000000840AC7094FEADC545C0E891133C9D4922C00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6Ma	01030000A034BF0D0001000000090000002CB73565142C42C028CB08BE514922C00000000000000840BC792B8E700B42C028CB08BE514922C00000000000000840BC792B8E700B42C058FCC28A664523C00000000000000840A835D992CD6A40C058FCC28A664523C00000000000000840A835D992CD6A40C030FB22BC115113C0000000000000084038D72A7BB11E42C030FB22BC115113C0000000000000084038D72A7BB11E42C040DB96D3CFC513C000000000000008402CB73565142C42C040DB96D3CFC513C000000000000008402CB73565142C42C028CB08BE514922C00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6Mf	01030000A034BF0D0001000000090000008846F85A3D5842C058FCC28A664523C000000000000008408846F85A3D5842C028CB08BE514922C000000000000008401809EE83993742C028CB08BE514922C000000000000008401809EE83993742C040DB96D3CFC513C000000000000008409C3D91E1174542C040DB96D3CFC513C000000000000008409C3D91E1174542C020937474305613C000000000000008407C66250F0EF943C020937474305613C000000000000008407C66250F0EF943C058FCC28A664523C000000000000008408846F85A3D5842C058FCC28A664523C00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6MZ	01030000A034BF0D00010000000C000000483F9DF14A7D3DC058FCC28A664523C00000000000000840483F9DF14A7D3DC0D0B72963FF4822C0000000000000084068C48843033C3DC0D0B72963FF4822C0000000000000084068C48843033C3DC000C064AF27C513C0000000000000084040086590FC563DC000C064AF27C513C0000000000000084040086590FC563DC020937474305613C0000000000000084000714B1FBF8C3FC020937474305613C00000000000000840B03C71D735A13FC020937474305613C00000000000000840B03C71D735A13FC030FB22BC115113C00000000000000840BCE32074485F40C030FB22BC115113C00000000000000840BCE32074485F40C058FCC28A664523C00000000000000840483F9DF14A7D3DC058FCC28A664523C00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6LM	01030000A034BF0D0001000000090000003ACDEA44728B49C058FCC28A664523C000000000000008403ACDEA44728B49C048A5F296EF4922C00000000000000840CA8FE06DCE6A49C048A5F296EF4922C00000000000000840CA8FE06DCE6A49C0301D87AD1CC713C000000000000008404255F15D4D7849C0301D87AD1CC713C000000000000008404255F15D4D7849C0706B396A593213C00000000000000840F2C9499EA5974AC0706B396A593213C00000000000000840F2C9499EA5974AC058FCC28A664523C000000000000008403ACDEA44728B49C058FCC28A664523C00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6LL	01030000A034BF0D000100000009000000E23D284F495F49C048A5F296EF4922C000000000000008406A001E78A53E49C048A5F296EF4922C000000000000008406A001E78A53E49C058FCC28A664523C0000000000000084022D1679D883248C058FCC28A664523C0000000000000084022D1679D883248C030FB22BC115113C00000000000000840DAEE8AF7E65149C030FB22BC115113C00000000000000840DAEE8AF7E65149C0301D87AD1CC713C00000000000000840E23D284F495F49C0301D87AD1CC713C00000000000000840E23D284F495F49C048A5F296EF4922C00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6Mt	01030000A034BF0D0001000000090000004887F064C2F135C0D057762BA64822C00000000000000840680CDCB67AB035C0D057762BA64822C00000000000000840680CDCB67AB035C058FCC28A664523C0000000000000084040158D6D449833C058FCC28A664523C0000000000000084040158D6D449833C030FB22BC115113C0000000000000084018B0DF90FCD635C030FB22BC115113C0000000000000084018B0DF90FCD635C080432FD689C413C000000000000008404887F064C2F135C080432FD689C413C000000000000008404887F064C2F135C0D057762BA64822C00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6Mu	01030000A034BF0D00010000000900000000A67550144A36C058FCC28A664523C0000000000000084000A67550144A36C0D057762BA64822C00000000000000840202B61A2CC0836C0D057762BA64822C00000000000000840202B61A2CC0836C080432FD689C413C00000000000000840E87CAC5DC92336C080432FD689C413C00000000000000840E87CAC5DC92336C020937474305613C0000000000000084090B785857D6238C020937474305613C0000000000000084090B785857D6238C058FCC28A664523C0000000000000084000A67550144A36C058FCC28A664523C00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6M_	01030000A034BF0D00010000000900000090201806F9243DC0D0B72963FF4822C00000000000000840B0A50358B1E33CC0D0B72963FF4822C00000000000000840B0A50358B1E33CC058FCC28A664523C00000000000000840B813154873CB3AC058FCC28A664523C00000000000000840B813154873CB3AC020937474305613C00000000000000840703B98C32F0A3DC020937474305613C00000000000000840703B98C32F0A3DC000C064AF27C513C0000000000000084090201806F9243DC000C064AF27C513C0000000000000084090201806F9243DC0D0B72963FF4822C00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6Ml	01030000A034BF0D000100000009000000080057F4D6F145C058FCC28A664523C00000000000000840080057F4D6F145C0E891133C9D4922C000000000000008401C8293AAA7D245C0E891133C9D4922C000000000000008401C8293AAA7D245C0E0FAC8F777C613C00000000000000840C09B92C4B3DE45C0E0FAC8F777C613C00000000000000840C09B92C4B3DE45C030FB22BC115113C00000000000000840102320BC0DFE46C030FB22BC115113C00000000000000840102320BC0DFE46C058FCC28A664523C00000000000000840080057F4D6F145C058FCC28A664523C00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6LS	01030000A034BF0D00010000000A00000022AC2B6103F74CC098A97F17474A22C000000000000008400AE5F51F0BC54CC098A97F17474A22C000000000000008400AE5F51F0BC54CC058FCC28A664523C000000000000008404A0E102420CC4BC058FCC28A664523C000000000000008404A0E102420CC4BC0706B396A593213C00000000000000840BA1CEC9080EB4CC0706B396A593213C00000000000000840BA1CEC9080EB4CC0704FD1F4BDC713C0000000000000084022AC2B6103F74CC0704FD1F4BDC713C0000000000000084022AC2B6103F74CC00015E8FE66611AC0000000000000084022AC2B6103F74CC098A97F17474A22C00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6Mn	01030000A034BF0D00010000000A00000090950CE5957A2EC058FCC28A664523C0000000000000084090950CE5957A2EC0B83ED187554822C00000000000000840E00946FE81B02DC0B83ED187554822C00000000000000840E00946FE81B02DC0E0D47EF7372A1CC00000000000000840E00946FE81B02DC070DA9843DEC313C000000000000008405042D4552CE12DC070DA9843DEC313C000000000000008405042D4552CE12DC020937474305613C00000000000000840F0FBD222C82E31C020937474305613C00000000000000840F0FBD222C82E31C058FCC28A664523C0000000000000084090950CE5957A2EC058FCC28A664523C00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6LR	01030000A034BF0D0001000000050000006ABC57059BC04BC0C06B396A593213C000000000000008406ABC57059BC04BC030FCC28A664523C00000000000000840D21B02BD2AA34AC030FCC28A664523C00000000000000840D21B02BD2AA34AC0C06B396A593213C000000000000008406ABC57059BC04BC0C06B396A593213C00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6Mo	01030000A034BF0D000100000008000000C89F4360D24531C058FCC28A664523C00000000000000840C89F4360D24531C020937474305613C00000000000000840D0CE647C4E4F32C020937474305613C00000000000000840A83BEC3AC56332C020937474305613C00000000000000840A83BEC3AC56332C030FB22BC115113C0000000000000084068711C303A8133C030FB22BC115113C0000000000000084068711C303A8133C058FCC28A664523C00000000000000840C89F4360D24531C058FCC28A664523C00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6LG	01030000A034BF0D0001000000050000003A7FAF7E032748C090FA22BC115113C000000000000008403A7FAF7E032748C0A8FCC28A664523C00000000000000840F874D8DA920947C0A8FCC28A664523C00000000000000840F874D8DA920947C090FA22BC115113C000000000000008403A7FAF7E032748C090FA22BC115113C00000000000000840
second_floor	1BUg4a4jr0B9Q5NnDgB6Mz	01030000A034BF0D0001000000050000000071A40A69B43AC030957474305613C000000000000008400071A40A69B43AC088FDC28A664523C00000000000000840805CF6C2877938C088FDC28A664523C00000000000000840805CF6C2877938C030957474305613C000000000000008400071A40A69B43AC030957474305613C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048il	01030000A034BF0D000100000007000000F05DA33F68DE20C0A0E046B84ECE02C00000000000000840F05DA33F68DE20C00060CB53C288CDBF0000000000000840A06942DA081229C00060CB53C288CDBF0000000000000840A06942DA081229C0803AACF1480202C00000000000000840E088EE88E2D128C0803AACF1480202C00000000000000840E088EE88E2D128C0A0E046B84ECE02C00000000000000840F05DA33F68DE20C0A0E046B84ECE02C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048ie	01030000A034BF0D00010000000500000000E4FFFFFFFFCFBF00CCE64694CD02C0000000000000084000E4FFFFFFFFCFBF002C00000000D0BF00000000000008406079F527AB7011C0002C00000000D0BF00000000000008406079F527AB7011C000CCE64694CD02C0000000000000084000E4FFFFFFFFCFBF00CCE64694CD02C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048l7	01030000A034BF0D00010000000A0000004080F1E91F1129C0C822E09DF14737C000000000000008404080F1E91F9128C0C822E09DF14737C000000000000008404080F1E91F9128C0D455E776FE4C37C00000000000000840F0A1A28ED95D21C0D455E776FE4C37C00000000000000840F0A1A28ED95D21C0C099A290244937C00000000000000840F05DA33F68DE20C0C099A290244937C00000000000000840F05DA33F68DE20C0FC6CBB21A11A37C00000000000000840F05DA33F68DE20C0846DACB4C13435C000000000000008404080F1E91F1129C0846DACB4C13435C000000000000008404080F1E91F1129C0C822E09DF14737C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048l0	01030000A034BF0D0001000000070000008080684564C428C068655E3C302033C000000000000008408080684564C428C0A019216DE05933C000000000000008404080F1E91F1129C0A019216DE05933C000000000000008404080F1E91F1129C00859FE6CE0F934C00000000000000840F05DA33F68DE20C00859FE6CE0F934C00000000000000840F05DA33F68DE20C068655E3C302033C000000000000008408080684564C428C068655E3C302033C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048lg	01030000A034BF0D00010000000A00000025690C80DE1852C07082A9B0681C33C0000000000000084025690C80DE1852C0D47D30D7415233C00000000000000840959FEC43F21652C0D47D30D7415233C00000000000000840959FEC43F21652C0B899BA20445234C0000000000000084039F7E498741252C0B899BA20445234C0000000000000084039F7E498741252C000AD1B735EE534C0000000000000084039548F320E2C51C000AD1B735EE534C0000000000000084039548F320E1C51C000AD1B735EE534C0000000000000084039548F320E1C51C07082A9B0681C33C0000000000000084025690C80DE1852C07082A9B0681C33C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048lE	01030000A034BF0D00010000000F000000F239625928584DC010F390590F9730C00000000000000840AA58E7447A304DC010F390590F9730C00000000000000840AA58E7447A304DC0A09878F413172DC00000000000000840AA58E7447A304DC0686545C1E0E32BC00000000000000840AA58E7447A304DC0E8665D4DB8C728C00000000000000840729D11BACC3A4DC0E8665D4DB8C728C0000000000000084012BF4DABE0564DC0E8665D4DB8C728C00000000000000840FA2C3D8DE0FF4DC0E8665D4DB8C728C00000000000000840FA2C3D8DE0FF4DC000245E4E0E412CC00000000000000840FA2C3D8DE0FF4DC0108DFC3F5C4A2CC0000000000000084072B89C2B97FE4DC0108DFC3F5C4A2CC0000000000000084072B89C2B97FE4DC0B8169694658F2CC0000000000000084072B89C2B97FE4DC008D6ECA4199730C00000000000000840020C8D8C5BDB4DC008D6ECA4199730C00000000000000840F239625928584DC010F390590F9730C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048iX	01030000A034BF0D00010000000500000080C1A53CD2D122C0A0D4C58B46B00AC0000000000000084080C1A53CD2D122C0F0F826E7590B13C00000000000000840405FA33F68DE20C0F0F826E7590B13C00000000000000840405FA33F68DE20C0A0D4C58B46B00AC0000000000000084080C1A53CD2D122C0A0D4C58B46B00AC00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048lL	01030000A034BF0D000100000005000000C060A43716140BC0208876BC630013C00000000000000840C060A43716140BC000616977349A0AC00000000000000840E078F527AB7011C000616977349A0AC00000000000000840E078F527AB7011C0208876BC630013C00000000000000840C060A43716140BC0208876BC630013C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048lB	01030000A034BF0D000100000005000000B2E6D39ACA9C4EC000C5D9A6D78F0AC00000000000000840B2E6D39ACA9C4EC040599F9BB6E112C000000000000008409AA11379631F4EC040599F9BB6E112C000000000000008409AA11379631F4EC000C5D9A6D78F0AC00000000000000840B2E6D39ACA9C4EC000C5D9A6D78F0AC00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048ia	01030000A034BF0D000100000005000000500787B7E6FF22C0A0D4C58B46B00AC0000000000000084030D2C3227CEB24C0A0D4C58B46B00AC0000000000000084030D2C3227CEB24C0F0F826E7590B13C00000000000000840500787B7E6FF22C0F0F826E7590B13C00000000000000840500787B7E6FF22C0A0D4C58B46B00AC00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048lJ	01030000A034BF0D000100000005000000C03A42E65DF501C0208876BC630013C0000000000000084080A6D4D7928EF4BF208876BC630013C0000000000000084080A6D4D7928EF4BF00616977349A0AC00000000000000840C03A42E65DF501C000616977349A0AC00000000000000840C03A42E65DF501C0208876BC630013C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048lM	01030000A034BF0D00010000000500000040421F4CC45B0AC0208876BC630013C00000000000000840C05AC7D1AFAD02C0208876BC630013C00000000000000840C05AC7D1AFAD02C000616977349A0AC0000000000000084040421F4CC45B0AC000616977349A0AC0000000000000084040421F4CC45B0AC0208876BC630013C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048ix	01030000A034BF0D000100000005000000201AA59D901925C0A0D4C58B46B00AC000000000000008402043946F050527C0A0D4C58B46B00AC000000000000008402043946F050527C0F0F826E7590B13C00000000000000840201AA59D901925C0F0F826E7590B13C00000000000000840201AA59D901925C0A0D4C58B46B00AC00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048lS	01030000A034BF0D000100000005000000006ACA00EF1DF3BF208876BC630013C000000000000008400070505BB6FDCFBF208876BC630013C000000000000008400070505BB6FDCFBF00616977349A0AC00000000000000840006ACA00EF1DF3BF00616977349A0AC00000000000000840006ACA00EF1DF3BF208876BC630013C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048lb	01030000A034BF0D000100000005000000B1E479D3279C51C0D06BAE083BFC12C000000000000008407125A72FB75E51C0D06BAE083BFC12C000000000000008407125A72FB75E51C0A01D6F3B8DC40AC00000000000000840B1E479D3279C51C0A01D6F3B8DC40AC00000000000000840B1E479D3279C51C0D06BAE083BFC12C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048lc	01030000A034BF0D000100000005000000EDCCA8065BDF51C0D06BAE083BFC12C00000000000000840B10DD662EAA151C0D06BAE083BFC12C00000000000000840B10DD662EAA151C0A01D6F3B8DC40AC00000000000000840EDCCA8065BDF51C0A01D6F3B8DC40AC00000000000000840EDCCA8065BDF51C0D06BAE083BFC12C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048ln	01030000A034BF0D000100000005000000A2878F6797A94FC040599F9BB6E112C000000000000008401A09EA1FB62E4FC040599F9BB6E112C000000000000008401A09EA1FB62E4FC000C5D9A6D78F0AC00000000000000840A2878F6797A94FC000C5D9A6D78F0AC00000000000000840A2878F6797A94FC040599F9BB6E112C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048lq	01030000A034BF0D00010000000500000022B7310131234FC040599F9BB6E112C00000000000000840AA388CB94FA84EC040599F9BB6E112C00000000000000840AA388CB94FA84EC000C5D9A6D78F0AC0000000000000084022B7310131234FC000C5D9A6D78F0AC0000000000000084022B7310131234FC040599F9BB6E112C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048lZ	01030000A034BF0D000100000005000000A9C0CB5D8B2252C06095D54154C50AC00000000000000840A9C0CB5D8B2252C02069AE083BFC12C00000000000000840E5F504961DE551C02069AE083BFC12C00000000000000840E5F504961DE551C0401A6F3B8DC40AC00000000000000840A9C0CB5D8B2252C06095D54154C50AC00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048i_	01030000A034BF0D000100000007000000A06942DA081229C050F726E7590B13C00000000000000840008C75EA193327C050F726E7590B13C00000000000000840008C75EA193327C0E0D7C58B46B00AC00000000000000840E088EE88E2D128C0E0D7C58B46B00AC00000000000000840E088EE88E2D128C0A067AFDDFECE0AC00000000000000840A06942DA081229C0A067AFDDFECE0AC00000000000000840A06942DA081229C050F726E7590B13C00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048lu	01030000A034BF0D00010000000500000069FC4AA0F45851C0A01D6F3B8DC40AC0000000000000084069FC4AA0F45851C0D06BAE083BFC12C00000000000000840556A378D2C1C51C0D06BAE083BFC12C00000000000000840556A378D2C1C51C0A01D6F3B8DC40AC0000000000000084069FC4AA0F45851C0A01D6F3B8DC40AC00000000000000840
second_floor	1mWTVVwiXDHQKYjSZ048lo	01030000A034BF0D00010000000500000072D947861CB54FC040599F9BB6E112C0000000000000084072D947861CB54FC000C5D9A6D78F0AC0000000000000084061A9037F0A1650C000C5D9A6D78F0AC0000000000000084061A9037F0A1650C040599F9BB6E112C0000000000000084072D947861CB54FC040599F9BB6E112C00000000000000840
\.


--
-- Data for Name: second_floor_edges; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.second_floor_edges (level, _area_id, _length, _id, source, target, geom) FROM stdin;
second_floor	1mWTVVwiXDHQKYjSZ048lE	1.12003121719965826	313	\N	\N	01020000A034BF0D0002000000B692D5108DFD4DC000245E4E0E412CC00000000000000440D24212692D984DC070E450AF8FAB2AC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lE	0.134848155992997931	314	\N	\N	01020000A034BF0D0002000000D24212692D984DC070E450AF8FAB2AC00000000000000440D24212692D984DC0880F09DE84662AC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.19507681063849702	315	\N	\N	01020000A034BF0D0003000000E675459C60B34DC090D498BCE34728C00000000000000440E675459C60B34DC0A0AD67B4372B27C00000000000000440E675459C60B34DC0980705A102E425C00000000000000440
second_floor	\N	0.249668621059001339	316	\N	\N	01020000A034BF0D0002000000E675459C60B34DC0E8665D4DB8C728C00000000000000440E675459C60B34DC090D498BCE34728C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lE	0.898174840006691566	317	\N	\N	01020000A034BF0D0004000000D24212692D984DC0880F09DE84662AC00000000000000440E675459C60B34DC038433C11B8F929C00000000000000440E675459C60B34DC0D88D8E5564E429C00000000000000440E675459C60B34DC0E8665D4DB8C728C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.662015579741099258	318	\N	\N	01020000A034BF0D0003000000E675459C60B34DC0980705A102E425C000000000000004409A429D7F36EF4DC0980705A102E425C00000000000000440E2C9D754D2004EC068EA1A4C939D25C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	4.26006738142456953	319	\N	\N	01020000A034BF0D0004000000E2C9D754D2004EC068EA1A4C939D25C00000000000000440321489B53AC94EC068EA1A4C939D25C00000000000000440F609B211CA4B4FC078C1BEBCD0A727C00000000000000440AEC273CF07EC4FC078C1BEBCD0A727C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.9677270889019951	320	\N	\N	01020000A034BF0D0002000000AEC273CF07EC4FC078C1BEBCD0A727C00000000000000440BB735325F37350C078C1BEBCD0A727C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.70822139073615609	321	\N	\N	01020000A034BF0D0003000000BB735325F37350C078C1BEBCD0A727C00000000000000440E110B007F77450C0A8AAA3CFEFAF27C0000000000000044007215CFFDAE050C0A8AAA3CFEFAF27C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lg	1.03229707249457059	322	\N	\N	01020000A034BF0D000500000039548F320E1C51C024CA8A2B7DAA33C00000000000000440DBB4E2DFEE3551C024CA8A2B7DAA33C00000000000000440539E0911F73551C0047026F09DAA33C000000000000004409F8F6E829B3F51C0047026F09DAA33C000000000000004408B99DDEA2C5551C0B897E291E30034C00000000000000440
second_floor	\N	0.25	323	\N	\N	01020000A034BF0D000200000039548F320E0C51C024CA8A2B7DAA33C0000000000000044039548F320E1C51C024CA8A2B7DAA33C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048kN	7.1830583027692958	324	\N	\N	01020000A034BF0D000800000007215CFFDAE050C08842CD9CEABD2CC0000000000000044007215CFFDAE050C07869FEA496DA2DC0000000000000044007215CFFDAE050C018DC663684172EC0000000000000044065ED8AABDE9850C0903C786AB32B30C00000000000000440E7B74B6BDC9850C0AC9BD5B4620533C000000000000004408503F90823C250C024CA8A2B7DAA33C000000000000004405B2F89B178E850C024CA8A2B7DAA33C0000000000000044039548F320E0C51C024CA8A2B7DAA33C00000000000000440
second_floor	\N	0.190521208191000824	325	\N	\N	01020000A034BF0D000200000007215CFFDAE050C0A882E09D5E5C2CC0000000000000044007215CFFDAE050C08842CD9CEABD2CC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.3367828797599941	326	\N	\N	01020000A034BF0D000300000007215CFFDAE050C0A8AAA3CFEFAF27C0000000000000044007215CFFDAE050C0B85BAF95B23F2BC0000000000000044007215CFFDAE050C0A882E09D5E5C2CC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lg	3.27866322730670579	327	\N	\N	01020000A034BF0D00060000008B99DDEA2C5551C0B897E291E30034C00000000000000440E7B196E055D951C0B897E291E30034C0000000000000044051D4E22AB9EB51C0140EB26856B733C00000000000000440AD7CEAD536F051C0140EB26856B733C0000000000000044029C01B1F371052C02400ED43553733C00000000000000440B9893B5B231252C02400ED43553733C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lg	0.908632209018369275	328	\N	\N	01020000A034BF0D00020000008B99DDEA2C5551C0B897E291E30034C0000000000000044039548F320E2C51C000AD1B735EA534C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.80000000000001137	329	\N	\N	01020000A034BF0D000200000007215CFFDAE050C0A8AAA3CFEFAF27C000000000000004403B548F320E5451C0A8AAA3CFEFAF27C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.889882495248997429	330	\N	\N	01020000A034BF0D00020000003B548F320E5451C0A8AAA3CFEFAF27C0000000000000044061EC4408028D51C0A8AAA3CFEFAF27C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.859309402660437427	331	\N	\N	01020000A034BF0D000300000061EC4408028D51C0A8AAA3CFEFAF27C00000000000000440F14DD1D4FB9F51C028B70634BE4728C00000000000000440F14DD1D4FB9F51C008321BE2052929C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.58714503115441952	332	\N	\N	01020000A034BF0D000300000061EC4408028D51C0A8AAA3CFEFAF27C00000000000000440416759B6498E51C098D3FF5EB2A527C000000000000004409D1B45160EF251C098D3FF5EB2A527C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.44685447965360581	333	\N	\N	01020000A034BF0D00050000009D1B45160EF251C098D3FF5EB2A527C000000000000004406DFF26F3334E52C018F20E46E1862AC0000000000000044079D6CA63715852C018F20E46E1862AC00000000000000440C9129CB2916052C090D498BCE3C72AC00000000000000440C9129CB2916052C090BCA57F49EC2AC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.37496728516698852	334	\N	\N	01020000A034BF0D0002000000C9129CB2916052C090BCA57F49EC2AC00000000000000440C9129CB2916052C0F875EB3545AC2FC00000000000000440
second_floor	\N	0.609587404679501788	335	\N	\N	01020000A034BF0D0002000000C9129CB2919052C090BCA57F49EC2AC0000000000000044083DC7F2D95B752C090BCA57F49EC2AC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.75	336	\N	\N	01020000A034BF0D0003000000C9129CB2916052C090BCA57F49EC2AC00000000000000440EBED9531FC6C52C090BCA57F49EC2AC00000000000000440C9129CB2919052C090BCA57F49EC2AC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	4.05106571891685352	337	\N	\N	01020000A034BF0D00050000009D1B45160EF251C098D3FF5EB2A527C0000000000000044019CCCFD36C5C52C0C04FAA72BC5224C0000000000000044019CCCFD36C5C52C0A8C57491D6A921C000000000000004401DB0D345E36152C088A55501237E21C000000000000004401DB0D345E36152C0C8AB83DC21FE20C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.65489527459048702	338	\N	\N	01020000A034BF0D00020000001DB0D345E36152C0C8AB83DC21FE20C000000000000004401DB0D345E36152C060A81CDBA65D1FC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048li	1.45346949794322655	339	\N	\N	01020000A034BF0D0004000000755CA765852252C0C8AB83DC21FE20C000000000000004409737A1E4EFFE51C0C8AB83DC21FE20C000000000000004405DFEC49CB4EE51C0C8AB83DC21FE20C0000000000000044041E5377191D151C0E8E21A80081520C00000000000000440
second_floor	\N	0.25	340	\N	\N	01020000A034BF0D0002000000755CA765853252C0C8AB83DC21FE20C00000000000000440755CA765852252C0C8AB83DC21FE20C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.740104716575501698	341	\N	\N	01020000A034BF0D00030000001DB0D345E36152C0C8AB83DC21FE20C000000000000004405381ADE61A5652C0C8AB83DC21FE20C00000000000000440755CA765853252C0C8AB83DC21FE20C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048li	1.56939305459496836	342	\N	\N	01020000A034BF0D000200000041E5377191D151C0E8E21A80081520C00000000000000440BDE1A681206D51C0E8E21A80081520C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048li	0.812508065997468498	343	\N	\N	01020000A034BF0D000300000041E5377191D151C0E8E21A80081520C000000000000004406D1D9B4B54EF51C02043025AE34D1EC000000000000004406D1D9B4B54EF51C0D088E7334CAF1DC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048li	0.452317861665538001	344	\N	\N	01020000A034BF0D00020000006D1D9B4B54EF51C0D088E7334CAF1DC000000000000004401D1F5481CC0352C0E06D57D8C8671CC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048li	1.82371771601757882	345	\N	\N	01020000A034BF0D00040000006D1D9B4B54EF51C0D088E7334CAF1DC000000000000004409548DAE5F0E851C0503BDAD715491DC000000000000004409548DAE5F0E851C0E0B95E18678B17C00000000000000440A18F30A7BFDD51C0B02AC32D53D816C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048li	0.454891787035023754	346	\N	\N	01020000A034BF0D0002000000A18F30A7BFDD51C0B02AC32D53D816C000000000000004406D6DBFB4A2C051C0B02AC32D53D816C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048li	1.04999999600187266	347	\N	\N	01020000A034BF0D00030000006D6DBFB4A2C051C0B02AC32D53D816C000000000000004402DF9271B099F51C0B02AC32D53D816C00000000000000440398590816F7D51C0B02AC32D53D816C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lb	0.920346444524519858	348	\N	\N	01020000A034BF0D0005000000398590816F7D51C0D06BAE083BFC12C00000000000000440398590816F7D51C010A3374A9B6111C00000000000000440398590816F7D51C0507418EAB51011C00000000000000440118590816F7D51C0D07118EAB51011C00000000000000440118590816F7D51C0A0119B78979B0EC00000000000000440
second_floor	\N	0.0899999999993923439	349	\N	\N	01020000A034BF0D0002000000398590816F7D51C080F870FE635813C00000000000000440398590816F7D51C0D06BAE083BFC12C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048li	0.874935855285499997	350	\N	\N	01020000A034BF0D0003000000398590816F7D51C0B02AC32D53D816C00000000000000440398590816F7D51C040C1E7BC03F314C00000000000000440398590816F7D51C080F870FE635813C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lu	0.942059195305055441	351	\N	\N	01020000A034BF0D0005000000D33D983A013851C0D06BAE083BFC12C00000000000000440D33D983A013851C010A3374A9B6111C00000000000000440D33D983A013851C0F033A132F03E11C000000000000004405F33C196903A51C030DB1170FA1511C000000000000004405F33C196903A51C0E03EA86C0E910EC00000000000000440
second_floor	\N	0.0899999999993923439	352	\N	\N	01020000A034BF0D0002000000D33D983A013851C080F870FE635813C00000000000000440D33D983A013851C0D06BAE083BFC12C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048li	1.70199870912001217	353	\N	\N	01020000A034BF0D0006000000398590816F7D51C0B02AC32D53D816C00000000000000440F110F9E7D55B51C0B02AC32D53D816C00000000000000440AD8D2C802B5451C0B02AC32D53D816C00000000000000440D33D983A013851C0202D7ED4AE1515C00000000000000440D33D983A013851C040C1E7BC03F314C00000000000000440D33D983A013851C080F870FE635813C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lc	0.920346444524489327	354	\N	\N	01020000A034BF0D00050000006D6DBFB4A2C051C0D06BAE083BFC12C000000000000004406D6DBFB4A2C051C010A3374A9B6111C000000000000004406D6DBFB4A2C051C0D07318EAB51011C000000000000004404F6DBFB4A2C051C0F07118EAB51011C000000000000004404F6DBFB4A2C051C060119B78979B0EC00000000000000440
second_floor	\N	0.0899999999993923439	355	\N	\N	01020000A034BF0D00020000006D6DBFB4A2C051C080F870FE635813C000000000000004406D6DBFB4A2C051C0D06BAE083BFC12C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048li	0.874935855285499997	356	\N	\N	01020000A034BF0D00030000006D6DBFB4A2C051C0B02AC32D53D816C000000000000004406D6DBFB4A2C051C040C1E7BC03F314C000000000000004406D6DBFB4A2C051C080F870FE635813C00000000000000440
second_floor	\N	0.0225805231300776586	357	\N	\N	01020000A034BF0D0002000000D34E483C5E0552C080F870FE635813C000000000000004401D5111D6630652C0E0D3E0610A4813C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048li	1.13135645983353728	358	\N	\N	01020000A034BF0D0005000000A18F30A7BFDD51C0B02AC32D53D816C000000000000004406DE1564E3CE251C0000E5EBB889016C00000000000000440ABCB273A3C0152C0206A4FFE89A014C00000000000000440ABCB273A3C0152C0002B7920849A13C00000000000000440D34E483C5E0552C080F870FE635813C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048li	0.311172288924506435	359	\N	\N	01020000A034BF0D00030000006753DA6F690752C080F870FE635813C000000000000004408988E9A0BB1352C0904A640F871D14C00000000000000440898BBC2C391652C0904A640F871D14C00000000000000440
second_floor	\N	0.0225805231300776586	360	\N	\N	01020000A034BF0D00020000001D5111D6630652C0E0D3E0610A4813C000000000000004406753DA6F690752C080F870FE635813C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lZ	0.936812411220175556	361	\N	\N	01020000A034BF0D00050000001D5111D6630652C02069AE083BFC12C000000000000004401D5111D6630652C060A0374A9B6111C000000000000004401D5111D6630652C06070078DC23911C00000000000000440475BE879D40352C0001378CACC1011C00000000000000440475BE879D40352C060AB1840CD9B0EC00000000000000440
second_floor	\N	0.074033158971985813	362	\N	\N	01020000A034BF0D00020000001D5111D6630652C0E0D3E0610A4813C000000000000004401D5111D6630652C02069AE083BFC12C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.60279257407976017	363	\N	\N	01020000A034BF0D0003000000BB735325F37350C078C1BEBCD0A727C0000000000000044099AA3DB0479850C0880A6D652C8526C0000000000000044099AA3DB0479850C0F070D3CB92EB20C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lf	2.57763976583958332	364	\N	\N	01020000A034BF0D0005000000AEC273CF07EC4FC0E849C9C798C22CC00000000000000440AEC273CF07EC4FC0F04E64329E912DC00000000000000440D23CD6B41FE84FC06066DA9C3EA12DC00000000000000440F2E190901FE84FC0E8ED6ED4A3CF2DC0000000000000044092957199842F4FC0407371D3FE5830C00000000000000440
second_floor	\N	0.199662503876993469	365	\N	\N	01020000A034BF0D0002000000AEC273CF07EC4FC0A882E09D5E5C2CC00000000000000440AEC273CF07EC4FC0E849C9C798C22CC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.35264495408100061	366	\N	\N	01020000A034BF0D0003000000AEC273CF07EC4FC078C1BEBCD0A727C00000000000000440AEC273CF07EC4FC0B85BAF95B23F2BC00000000000000440AEC273CF07EC4FC0A882E09D5E5C2CC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lf	1.00507820220856714	367	\N	\N	01020000A034BF0D000200000092957199842F4FC0407371D3FE5830C0000000000000044046EE2307832F4FC0B8F184A14B5A31C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lf	2.44402523131375293	368	\N	\N	01020000A034BF0D000300000046EE2307832F4FC0B8F184A14B5A31C000000000000004406A2EAB61AB534EC0747176ECFA1133C0000000000000044002377E00BD514EC0747176ECFA1133C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lf	1.63523659334367766	369	\N	\N	01020000A034BF0D000500000046EE2307832F4FC0B8F184A14B5A31C0000000000000044092032CB724304FC084AB7B098F5B31C00000000000000440CED4E12623304FC06425F029925B32C00000000000000440CA0EAB76EE344FC0E01B7B05296532C0000000000000044066B76A90ED344FC03C09A0E36BF832C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lf	0.691453692809355314	370	\N	\N	01020000A034BF0D000300000092957199842F4FC0407371D3FE5830C0000000000000044042BB83FCD6FF4EC0487D2B3347F32FC000000000000004404A4575C6C2EA4EC0487D2B3347F32FC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.66046322993175144	371	\N	\N	01020000A034BF0D0005000000E2C9D754D2004EC068EA1A4C939D25C000000000000004406E93B35419AB4DC098108A4BAF4624C000000000000004406E93B35419AB4DC07808F2107FA721C000000000000004403AF6335C46984DC0A893F32E335C21C000000000000004403AF6335C46984DC01084700FA3F820C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048l$	1.46276510858943487	372	\N	\N	01020000A034BF0D0004000000A2A11379631F4EC01084700FA3F820C000000000000004405EEB1F7B8E664EC01084700FA3F820C000000000000004407A4584B66D864EC01084700FA3F820C000000000000004400A196671F6C14EC0C035E923800A20C00000000000000440
second_floor	\N	0.24557595177998337	373	\N	\N	01020000A034BF0D000200000082D7AE70F4FF4DC01084700FA3F820C00000000000000440A2A11379631F4EC01084700FA3F820C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.810000000000002274	374	\N	\N	01020000A034BF0D00030000003AF6335C46984DC01084700FA3F820C00000000000000440C68DA26EC9B84DC01084700FA3F820C0000000000000044082D7AE70F4FF4DC01084700FA3F820C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048l$	1.55894712300903393	375	\N	\N	01020000A034BF0D00020000000A196671F6C14EC0C035E923800A20C000000000000004403ADBB40582894FC0C035E923800A20C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048l$	0.80622524884276614	376	\N	\N	01020000A034BF0D00030000000A196671F6C14EC0C035E923800A20C000000000000004407E87972A08874EC010DF5D118E3D1EC000000000000004407E87972A08874EC090AF1EB1B49E1DC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048l$	1.8189075880607759	377	\N	\N	01020000A034BF0D00060000007E87972A08874EC090AF1EB1B49E1DC0000000000000044046341E279A904EC05049E9CC24521DC0000000000000044046341E279A904EC05049E9CC24521CC00000000000000440C6B3B7C033924EC0504D1D0058451CC00000000000000440C6B3B7C033924EC0D0EDF74D105A17C000000000000004403637CF3EBAA54EC050D23B5DDCBD16C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048l$	0.500186748687241334	378	\N	\N	01020000A034BF0D00020000003637CF3EBAA54EC050D23B5DDCBD16C00000000000000440C2F75E5DC0E54EC050D23B5DDCBD16C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048l$	1.0499999960019295	379	\N	\N	01020000A034BF0D0003000000C2F75E5DC0E54EC050D23B5DDCBD16C0000000000000044022E08D90F3284FC050D23B5DDCBD16C0000000000000044032C8BCC3266C4FC050D23B5DDCBD16C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lo	0.961856137703103187	380	\N	\N	01020000A034BF0D0005000000A681797AB7F54FC040599F9BB6E112C00000000000000440B681797AB7F54FC0809028DD164711C00000000000000440B2FD58403CF74FC0C0B02CAEF03A11C000000000000004401A9627C298F04FC00074A1BCD40511C000000000000004401A9627C298F04FC0808FD5649B470EC00000000000000440
second_floor	\N	0.090000000000358682	381	\N	\N	01020000A034BF0D0002000000A281797AB7F54FC030EA6191DF3D13C00000000000000440A681797AB7F54FC040599F9BB6E112C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048l$	1.68596100092194856	382	\N	\N	01020000A034BF0D000600000032C8BCC3266C4FC050D23B5DDCBD16C000000000000004409AB0EBF659AF4FC050D23B5DDCBD16C000000000000004409E158C6415BC4FC050D23B5DDCBD16C000000000000004409281797AB7F54FC0C072D0ADCBF014C000000000000004409281797AB7F54FC0F0B2D84F7FD814C00000000000000440A281797AB7F54FC030EA6191DF3D13C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048ln	0.952910487115769422	383	\N	\N	01020000A034BF0D000500000046C8BCC3266C4FC040599F9BB6E112C0000000000000044056C8BCC3266C4FC0809028DD164711C0000000000000044072BBBE1935714FC0C0F7182DA41E11C000000000000004405EC8BCC3266C4FC0205F097D31F610C000000000000004405EC8BCC3266C4FC040B905E4E1660EC00000000000000440
second_floor	\N	0.090000000000358682	384	\N	\N	01020000A034BF0D000200000042C8BCC3266C4FC030EA6191DF3D13C0000000000000044046C8BCC3266C4FC040599F9BB6E112C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048l$	0.874987778830501384	385	\N	\N	01020000A034BF0D000300000032C8BCC3266C4FC050D23B5DDCBD16C0000000000000044032C8BCC3266C4FC0F0B2D84F7FD814C0000000000000044042C8BCC3266C4FC030EA6191DF3D13C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lq	0.952910487115782523	386	\N	\N	01020000A034BF0D0005000000D6F75E5DC0E54EC040599F9BB6E112C00000000000000440EAF75E5DC0E54EC0809028DD164711C00000000000000440FAEA60B3CEEA4EC010F8182DA41E11C00000000000000440E6F75E5DC0E54EC0605F097D31F610C00000000000000440E6F75E5DC0E54EC0C0B805E4E1660EC00000000000000440
second_floor	\N	0.090000000000358682	387	\N	\N	01020000A034BF0D0002000000D2F75E5DC0E54EC030EA6191DF3D13C00000000000000440D6F75E5DC0E54EC040599F9BB6E112C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048l$	0.874987778830501384	388	\N	\N	01020000A034BF0D0003000000C2F75E5DC0E54EC050D23B5DDCBD16C00000000000000440C2F75E5DC0E54EC0F0B2D84F7FD814C00000000000000440D2F75E5DC0E54EC030EA6191DF3D13C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lB	0.952486239310288418	389	\N	\N	01020000A034BF0D0007000000FAF10F4A34644EC040599F9BB6E112C00000000000000440FEF10F4A34644EC070CC836B12CA11C00000000000000440B60F302A8D624EC010BA846CD9BC11C00000000000000440BA0F302A8D624EC0709028DD164711C00000000000000440AA8E9AE601664EC00099D4F9702B11C0000000000000044026C4F309175E4EC0E0449E141AEC10C0000000000000044026C4F309175E4EC0C0EDDBB4107B0EC00000000000000440
second_floor	\N	0.090000000000358682	390	\N	\N	01020000A034BF0D0002000000FAF10F4A34644EC030EA6191DF3D13C00000000000000440FAF10F4A34644EC040599F9BB6E112C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048l$	1.0870239143252507	391	\N	\N	01020000A034BF0D00060000003637CF3EBAA54EC050D23B5DDCBD16C00000000000000440A20F302A8DA24EC0B09542B873A416C000000000000004406E71A9E3CD654EC020A40D8479BE14C000000000000004407671A9E3CD654EC040FF09E051C713C00000000000000440F6F10F4A34644EC030033E1385BA13C00000000000000440FAF10F4A34644EC030EA6191DF3D13C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048l$	0.438053546813286288	392	\N	\N	01020000A034BF0D00020000007E87972A08874EC090AF1EB1B49E1DC00000000000000440662FF341625F4EC0D0EEFB6B85611CC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.580499591417009242	393	\N	\N	01020000A034BF0D00020000003AF6335C46984DC01084700FA3F820C000000000000004403AF6335C46984DC0401FBFA2D79E1FC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.26200636282128364	394	\N	\N	01020000A034BF0D0004000000E675459C60B34DC0980705A102E425C000000000000004408226E87938914DC0980705A102E425C00000000000000440724E5296058E4DC068A7AD1237D725C00000000000000440F6B180612A134CC068A7AD1237D725C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.3199890916921504	395	\N	\N	01020000A034BF0D0002000000F6B180612A134CC068A7AD1237D725C0000000000000044076BF72FA34EA4AC068A7AD1237D725C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.45180680600108891	396	\N	\N	01020000A034BF0D000300000076BF72FA34EA4AC068A7AD1237D725C00000000000000440424BE702AE954AC068A7AD1237D725C000000000000004402230B0040C4E4AC0E0138A0BBFF526C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.523780672107459488	397	\N	\N	01020000A034BF0D00020000002230B0040C4E4AC0E0138A0BBFF526C000000000000004406AA776C5A31E4AC0C836700860B327C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.28957874988998356	398	\N	\N	01020000A034BF0D00020000006AA776C5A31E4AC0C836700860B327C00000000000000440FA74D8DA927948C0C836700860B327C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15905238501267149	399	\N	\N	01020000A034BF0D0002000000FA74D8DA927948C0C836700860B327C000000000000004408277BC0637E547C0C836700860B327C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.16094761498732169	400	\N	\N	01020000A034BF0D00020000008277BC0637E547C0C836700860B327C00000000000000440D21849189D5047C0C836700860B327C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6LG	3.9233383377832256	401	\N	\N	01020000A034BF0D0006000000D21849189D5047C0A8FCC28A664523C00000000000000440D21849189D5047C058F72720617622C00000000000000440C2EB967AAD5047C098ABF0961F7622C00000000000000440C2EB967AAD5047C07821C90BFC2822C000000000000004401AFAC32C4B9847C028E81443850A21C000000000000004401AFAC32C4B9847C090237F4BD4C617C00000000000000440
second_floor	\N	0.114707788247855547	402	\N	\N	01020000A034BF0D0002000000D21849189D5047C0A03A7185218023C00000000000000440D21849189D5047C0A8FCC28A664523C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.10008630144700703	403	\N	\N	01020000A034BF0D0003000000D21849189D5047C0C836700860B327C00000000000000440D21849189D5047C09061A28DCD9C24C00000000000000440D21849189D5047C0A03A7185218023C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.0390523850126669458	404	\N	\N	01020000A034BF0D0002000000D21849189D5047C0C836700860B327C00000000000000440EADD226D9D4B47C0C836700860B327C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.854913698552337564	405	\N	\N	01020000A034BF0D0002000000EADD226D9D4B47C0C836700860B327C0000000000000044046C63E9D2FDE46C0C836700860B327C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.432797315168529095	406	\N	\N	01020000A034BF0D000200000046C63E9D2FDE46C0C836700860B327C00000000000000440387FAF7E03B746C0901A338EAF1627C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6Ml	3.95795003603080264	407	\N	\N	01020000A034BF0D000A000000387FAF7E03B746C058FCC28A664523C00000000000000440387FAF7E03B746C060F72720617622C0000000000000044046AC611CF3B646C098ABF0961F7622C0000000000000044046AC611CF3B646C03021C90BFC2822C000000000000004408C913B58F27746C048B630FBF82C21C000000000000004408C913B58F27746C0D84B81AC2F3120C0000000000000044096D259B35A6846C000A0F431A2E51FC0000000000000044096D259B35A6846C0B07EFB3D107418C00000000000000440685F59C0606E46C02018FFD5DF4318C00000000000000440685F59C0606E46C07018599A79CE17C00000000000000440
second_floor	\N	0.114707788247997655	408	\N	\N	01020000A034BF0D0002000000387FAF7E03B746C0A03A7185218023C00000000000000440387FAF7E03B746C058FCC28A664523C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.7940523850120087	409	\N	\N	01020000A034BF0D0003000000387FAF7E03B746C0901A338EAF1627C00000000000000440387FAF7E03B746C09061A28DCD9C24C00000000000000440387FAF7E03B746C0A03A7185218023C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.10579208869931866	410	\N	\N	01020000A034BF0D0003000000387FAF7E03B746C0901A338EAF1627C00000000000000440AA2CA503966446C058D009A2F9CC25C00000000000000440085C4E6B9D4B45C058D009A2F9CC25C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6Mg	5.12462571842970682	411	\N	\N	01020000A034BF0D000B000000085C4E6B9D4B45C058FCC28A664523C00000000000000440085C4E6B9D4B45C068D59182BA2822C00000000000000440085C4E6B9D4B45C0889FD399B3DF21C00000000000000440D2F5B3AACED444C0B0066A97780420C00000000000000440D2F5B3AACED444C0803875915E111EC000000000000004408A14399620E544C0C0424C35CF8E1DC000000000000004408A14399620E544C0F0DBA33AE3CA1AC00000000000000440E2F6044670DE44C0B0EE02B960951AC00000000000000440E2F6044670DE44C000EF5C7DFA1F1AC000000000000004408E522D8DDA6A45C0A0111A44A8BC15C000000000000004408E522D8DDA6A45C0B0E176D36AB215C00000000000000440
second_floor	\N	0.114707788247997655	412	\N	\N	01020000A034BF0D0002000000085C4E6B9D4B45C0A03A7185218023C00000000000000440085C4E6B9D4B45C058FCC28A664523C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144698998	413	\N	\N	01020000A034BF0D0003000000085C4E6B9D4B45C058D009A2F9CC25C00000000000000440085C4E6B9D4B45C09061A28DCD9C24C00000000000000440085C4E6B9D4B45C0A03A7185218023C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	4.29999999999999716	414	\N	\N	01020000A034BF0D0002000000085C4E6B9D4B45C058D009A2F9CC25C00000000000000440A2F5E704372543C058D009A2F9CC25C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6Mf	3.18415612345224641	415	\N	\N	01020000A034BF0D0009000000A2F5E704372543C058FCC28A664523C00000000000000440A2F5E704372543C068D59182BA2822C00000000000000440A2F5E704372543C0F03F04E37F1120C0000000000000044082D60EB5A52843C070BC6822C50320C0000000000000044082D60EB5A52843C080165DAB600F1EC00000000000000440CAB789C9531843C0C020344FD18C1DC00000000000000440CAB789C9531843C0D0507400A2CB1AC000000000000004400C525BF8121F43C0C07EE789A8951AC000000000000004400C525BF8121F43C0A036C52A09261AC00000000000000440
second_floor	\N	0.114707788247997655	416	\N	\N	01020000A034BF0D0002000000A2F5E704372543C0A03A7185218023C00000000000000440A2F5E704372543C058FCC28A664523C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144698998	417	\N	\N	01020000A034BF0D0003000000A2F5E704372543C058D009A2F9CC25C00000000000000440A2F5E704372543C09061A28DCD9C24C00000000000000440A2F5E704372543C0A03A7185218023C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.70134294243050022	418	\N	\N	01020000A034BF0D0002000000A2F5E704372543C058D009A2F9CC25C000000000000004402673E369714B41C058D009A2F9CC25C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6Ma	3.23097174319741232	419	\N	\N	01020000A034BF0D00090000002673E369714B41C058FCC28A664523C000000000000004402673E369714B41C068D59182BA2822C000000000000004402673E369714B41C000E2A2F9694520C00000000000000440B25782101F3B41C030741E94200420C00000000000000440B25782101F3B41C00086C88E17101EC000000000000004406A7607FC704B41C040909F32888D1DC000000000000004406A7607FC704B41C050E1081DEBCA1AC0000000000000044070060287BF4441C08061DD745F951AC0000000000000044070060287BF4441C07081695DA1201AC00000000000000440
second_floor	\N	0.114707788247997655	420	\N	\N	01020000A034BF0D00020000002673E369714B41C0A03A7185218023C000000000000004402673E369714B41C058FCC28A664523C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144698998	421	\N	\N	01020000A034BF0D00030000002673E369714B41C058D009A2F9CC25C000000000000004402673E369714B41C09061A28DCD9C24C000000000000004402673E369714B41C0A03A7185218023C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.00464200410081617	422	\N	\N	01020000A034BF0D00020000002673E369714B41C058D009A2F9CC25C00000000000000440A28CEF4DD9CA40C058D009A2F9CC25C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.39535799589918952	423	\N	\N	01020000A034BF0D0002000000A28CEF4DD9CA40C058D009A2F9CC25C00000000000000440E47F606D7C303EC058D009A2F9CC25C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6MZ	5.18212757021347681	424	\N	\N	01020000A034BF0D000C000000E47F606D7C303EC058FCC28A664523C00000000000000440E47F606D7C303EC068D59182BA2822C00000000000000440E47F606D7C303EC0207B3C9303DF21C000000000000004406083EFECED1D3FC028741E94200420C000000000000004406083EFECED1D3FC0405F0AD9720F1EC00000000000000440F045E5154AFD3EC08069E17CE38C1DC00000000000000440F045E5154AFD3EC020C6D6F842CA1AC00000000000000440DC6753BCC60A3FC0703E1E5F50941AC00000000000000440DC6753BCC60A3FC090112E2459251AC0000000000000044000714B1FBF8C3FC000ED4D98771D18C000000000000004400AC1ECAFF11740C0B0A81596E69015C000000000000004400AC1ECAFF11740C0C010C4DDC78B15C00000000000000440
second_floor	\N	0.114707788247997655	425	\N	\N	01020000A034BF0D0002000000E47F606D7C303EC0A03A7185218023C00000000000000440E47F606D7C303EC058FCC28A664523C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144698998	426	\N	\N	01020000A034BF0D0003000000E47F606D7C303EC058D009A2F9CC25C00000000000000440E47F606D7C303EC09061A28DCD9C24C00000000000000440E47F606D7C303EC0A03A7185218023C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.10308066398400362	427	\N	\N	01020000A034BF0D0003000000E47F606D7C303EC058D009A2F9CC25C000000000000004409CC3B1EA53FC3BC058D009A2F9CC25C00000000000000440F45BF6C287593BC0A89F80F1911227C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.401738954249359848	428	\N	\N	01020000A034BF0D0002000000F45BF6C287593BC0A89F80F1911227C00000000000000440AC71F9CBCE103BC038747ADF03A427C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.876277176621883314	429	\N	\N	01020000A034BF0D0002000000AC71F9CBCE103BC038747ADF03A427C00000000000000440309F81187B303AC038747ADF03A427C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.0396504845615908152	430	\N	\N	01020000A034BF0D0002000000309F81187B303AC038747ADF03A427C00000000000000440C428C38F54263AC038747ADF03A427C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6Mz	3.91833833780180285	431	\N	\N	01020000A034BF0D0006000000C428C38F54263AC088FDC28A664523C00000000000000440C428C38F54263AC070F72720617622C00000000000000440248327CB33263AC038ACF0961F7622C00000000000000440248327CB33263AC0D821C90BFC2822C00000000000000440C066CD66F89639C008E91443850A21C00000000000000440C066CD66F89639C030BED003F3CB17C00000000000000440
second_floor	\N	0.114707788247457643	432	\N	\N	01020000A034BF0D0002000000C428C38F54263AC0A03A7185218023C00000000000000440C428C38F54263AC088FDC28A664523C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.07008630144700589	433	\N	\N	01020000A034BF0D0003000000C428C38F54263AC038747ADF03A427C00000000000000440C428C38F54263AC09061A28DCD9C24C00000000000000440C428C38F54263AC0A03A7185218023C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.16034951543841203	434	\N	\N	01020000A034BF0D0002000000C428C38F54263AC038747ADF03A427C00000000000000440FC6B4EE547FD38C038747ADF03A427C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15965048456159536	435	\N	\N	01020000A034BF0D0002000000FC6B4EE547FD38C038747ADF03A427C000000000000004407070A40A69D437C038747ADF03A427C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6Mu	3.95762947996184522	436	\N	\N	01020000A034BF0D000A0000007070A40A69D437C058FCC28A664523C000000000000004407070A40A69D437C070F72720617622C0000000000000044044CA084648D437C018ABF0961F7622C0000000000000044044CA084648D437C0C021C90BFC2822C00000000000000440C8AEFDEA485637C0C8EAB255FD2C21C00000000000000440C8AEFDEA485637C0404666F63C3020C000000000000004405871F313A53537C0C096A390EADD1FC000000000000004405871F313A53537C0605C789CEB7718C000000000000004403C1A9971234337C0D0B8E125F24118C000000000000004403C1A9971234337C0700827C498D317C00000000000000440
second_floor	\N	0.114707788247997655	437	\N	\N	01020000A034BF0D00020000007070A40A69D437C0A03A7185218023C000000000000004407070A40A69D437C058FCC28A664523C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.07008630144700589	438	\N	\N	01020000A034BF0D00030000007070A40A69D437C038747ADF03A427C000000000000004407070A40A69D437C09061A28DCD9C24C000000000000004407070A40A69D437C0A03A7185218023C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.32389973592249532	439	\N	\N	01020000A034BF0D00020000007070A40A69D437C038747ADF03A427C000000000000004401478CFF27D8134C038747ADF03A427C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.503508032058706312	440	\N	\N	01020000A034BF0D00020000001478CFF27D8134C038747ADF03A427C00000000000000440645D6EE8582634C0D83EB8CAB9ED26C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6Mt	3.9622646719017891	441	\N	\N	01020000A034BF0D000A000000645D6EE8582634C058FCC28A664523C00000000000000440645D6EE8582634C078F72720617622C000000000000004400C030AAD792634C028ACF0961F7622C000000000000004400C030AAD792634C0B820C90BFC2822C00000000000000440D49034925FA434C030057441302D21C00000000000000440D49034925FA434C0A86027E26F3020C0000000000000044044CE3E6903C534C090CB256850DE1FC0000000000000044044CE3E6903C534C09027F6C4857718C00000000000000440AC62367FA0B734C03079D41CFA4118C00000000000000440AC62367FA0B734C0E030C80282CE17C00000000000000440
second_floor	\N	0.114707788247997655	442	\N	\N	01020000A034BF0D0002000000645D6EE8582634C0A03A7185218023C00000000000000440645D6EE8582634C058FCC28A664523C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.71405235759640107	443	\N	\N	01020000A034BF0D0003000000645D6EE8582634C0D83EB8CAB9ED26C00000000000000440645D6EE8582634C09061A28DCD9C24C00000000000000440645D6EE8582634C0A03A7185218023C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.43360238917515526	444	\N	\N	01020000A034BF0D0003000000645D6EE8582634C0D83EB8CAB9ED26C00000000000000440242617D4F89533C058D009A2F9CC25C00000000000000440302A3BB525F332C058D009A2F9CC25C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.32205279391750707	445	\N	\N	01020000A034BF0D0002000000302A3BB525F332C058D009A2F9CC25C0000000000000044024B4F1A7B3A030C058D009A2F9CC25C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.9178310959694298	446	\N	\N	01020000A034BF0D000500000024B4F1A7B3A030C058D009A2F9CC25C0000000000000044018027883EFD92AC058D009A2F9CC25C00000000000000440005430A274C52AC0707E518374E125C00000000000000440409B7122B0CE29C0707E518374E125C0000000000000044070E5CB16888E29C0A0C8AB774CA125C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.93730044359985509	447	\N	\N	01020000A034BF0D000300000070E5CB16888E29C0A0C8AB774CA125C00000000000000440309E8A964C8526C0A0C8AB774CA125C00000000000000440F8788019788324C0D8EDB5F420A327C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.947386558761976971	448	\N	\N	01020000A034BF0D0002000000F8788019788324C0D8EDB5F420A327C00000000000000440005EA33F689E22C0D8EDB5F420A327C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	3.4578409906098031	449	\N	\N	01020000A034BF0D0003000000005EA33F689E22C0D8EDB5F420A327C00000000000000440307E2672317617C0D8EDB5F420A327C0000000000000044060347A8B256C17C0F0C85F011B9E27C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.667420586134525706	450	\N	\N	01020000A034BF0D000200000060347A8B256C17C0F0C85F011B9E27C0000000000000044070B4213EB5C014C0F0C85F011B9E27C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.62163611922146345	451	\N	\N	01020000A034BF0D000200000070B4213EB5C014C0F0C85F011B9E27C0000000000000044080DCB2204E8804C0F0C85F011B9E27C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	5.61584703285852438	452	\N	\N	01020000A034BF0D000800000080DCB2204E8804C0F0C85F011B9E27C0000000000000044040EC9874CF43FCBF582FC667810426C000000000000004400010C12DEE49CFBF582FC667810426C00000000000000440001AE6296770CABF582FC667810426C00000000000000440006C7057943EE53F3090A785D64624C00000000000000440006C7057943EE53F3871BE76A2A421C00000000000000440004C1A109A22E93F38D3331B626621C00000000000000440004C1A109A22E93F28897F828FFD20C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lP	1.42077893475734118	453	\N	\N	01020000A034BF0D00040000000010C12DEE49CFBF28897F828FFD20C000000000000004400023C0181341E6BF28897F828FFD20C00000000000000440402BE47CB0A0F0BF28897F828FFD20C0000000000000044040BDD35CC1B5F7BFE8968166ED1A20C00000000000000440
second_floor	\N	0.25	454	\N	\N	01020000A034BF0D00020000000000DE473AC2763F28897F828FFD20C000000000000004400010C12DEE49CFBF28897F828FFD20C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.779917529860995273	455	\N	\N	01020000A034BF0D0003000000004C1A109A22E93F28897F828FFD20C000000000000004400037BF033838DD3F28897F828FFD20C000000000000004400000DE473AC2763F28897F828FFD20C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lP	1.64072386883400156	456	\N	\N	01020000A034BF0D000200000040BDD35CC1B5F7BFE8968166ED1A20C0000000000000044080235D8414FB08C0E8968166ED1A20C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lP	0.833029560556820092	457	\N	\N	01020000A034BF0D000300000040BDD35CC1B5F7BFE8968166ED1A20C0000000000000044080F5B51E2CD5F0BFF0BB7B7DB57D1EC0000000000000044080F5B51E2CD5F0BFE088E89125971DC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lP	1.78292440942558983	458	\N	\N	01020000A034BF0D000400000080F5B51E2CD5F0BFE088E89125971DC00000000000000440C03593FF666FF2BFD038B1D996301DC00000000000000440C03593FF666FF2BF802C0BADBDAB17C0000000000000044000172739EF64F5BF4034A69E5BEE16C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lP	0.4276658036609291	459	\N	\N	01020000A034BF0D000200000000172739EF64F5BF4034A69E5BEE16C00000000000000440C08C2C52A73CFCBF4034A69E5BEE16C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lP	1.04999999600188687	460	\N	\N	01020000A034BF0D0003000000C08C2C52A73CFCBF4034A69E5BEE16C00000000000000440C0CA04DC865102C04034A69E5BEE16C00000000000000440004DF30EBA8406C04034A69E5BEE16C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lL	0.954043667811909302	461	\N	\N	01020000A034BF0D00050000008060E6C8A14C0FC0208876BC630013C000000000000004408060E6C8A14C0FC060BFFFFDC36511C000000000000004408060E6C8A14C0FC0803FF478093611C0000000000000044040A9C743B6FA0EC0E0E364B6130D11C0000000000000044040A9C743B6FA0EC080A98C83D4800EC00000000000000440
second_floor	\N	0.0899999999999323563	462	\N	\N	01020000A034BF0D00020000008060E6C8A14C0FC0301739B28C5C13C000000000000004408060E6C8A14C0FC0208876BC630013C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lP	1.72945421111938025	463	\N	\N	01020000A034BF0D0006000000004DF30EBA8406C04034A69E5BEE16C0000000000000044040D2E141EDB70AC04034A69E5BEE16C00000000000000440E0B61077B8BD0BC04034A69E5BEE16C000000000000004408060E6C8A14C0FC0705FBBF5E62615C000000000000004408060E6C8A14C0FC0F0DFAF702CF714C000000000000004408060E6C8A14C0FC0301739B28C5C13C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lM	0.945085081031279639	464	\N	\N	01020000A034BF0D0005000000004DF30EBA8406C0208876BC630013C00000000000000440004DF30EBA8406C060BFFFFDC36511C00000000000000440004DF30EBA8406C0008FE09DDE1411C00000000000000440804EF30EBA8406C0408EE09DDE1411C00000000000000440804EF30EBA8406C0C05495B43E710EC00000000000000440
second_floor	\N	0.0899999999999323563	465	\N	\N	01020000A034BF0D0002000000004DF30EBA8406C0301739B28C5C13C00000000000000440004DF30EBA8406C0208876BC630013C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lP	0.892390913162003585	466	\N	\N	01020000A034BF0D0003000000004DF30EBA8406C04034A69E5BEE16C00000000000000440004DF30EBA8406C0F0DFAF702CF714C00000000000000440004DF30EBA8406C0301739B28C5C13C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lJ	0.94508508103123845	467	\N	\N	01020000A034BF0D0005000000C08C2C52A73CFCBF208876BC630013C00000000000000440C08C2C52A73CFCBF60BFFFFDC36511C00000000000000440C08C2C52A73CFCBF908EE09DDE1411C00000000000000440008E2C52A73CFCBF408EE09DDE1411C00000000000000440008E2C52A73CFCBFC05495B43E710EC00000000000000440
second_floor	\N	0.0899999999999323563	468	\N	\N	01020000A034BF0D0002000000C08C2C52A73CFCBF301739B28C5C13C00000000000000440C08C2C52A73CFCBF208876BC630013C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lP	0.892390913162003585	469	\N	\N	01020000A034BF0D0003000000C08C2C52A73CFCBF4034A69E5BEE16C00000000000000440C08C2C52A73CFCBFF0DFAF702CF714C00000000000000440C08C2C52A73CFCBF301739B28C5C13C00000000000000440
second_floor	\N	0.0429537524212110847	470	\N	\N	01020000A034BF0D000300000000B15DBEEEBAE8BF301739B28C5C13C0000000000000044000B15DBEEEBAE8BF604FF6650A5913C000000000000004400092B9B7F7D5E7BF80CB21856B3C13C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lP	1.12614127079994719	471	\N	\N	01020000A034BF0D000600000000172739EF64F5BF4034A69E5BEE16C0000000000000044000864FEC40D6F3BF1050700BB08A16C00000000000000440808E2A5D2E73E9BF60C0019C85C314C00000000000000440808E2A5D2E73E9BFD0E0F8B5A13214C0000000000000044000B15DBEEEBAE8BF20451FC2991B14C0000000000000044000B15DBEEEBAE8BF301739B28C5C13C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lS	0.961965972508309508	472	\N	\N	01020000A034BF0D00050000000092B9B7F7D5E7BF208876BC630013C000000000000004400092B9B7F7D5E7BF60BFFFFDC36511C000000000000004400092B9B7F7D5E7BFE01F3BF3A63311C00000000000000440007834CCA51DE7BFA07CCAB59C1C11C00000000000000440007834CCA51DE7BF0078C184C2610EC00000000000000440
second_floor	\N	0.0586234430819274621	473	\N	\N	01020000A034BF0D00020000000092B9B7F7D5E7BF80CB21856B3C13C000000000000004400092B9B7F7D5E7BF208876BC630013C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lP	0.355302154765635703	474	\N	\N	01020000A034BF0D00030000008034FF4EEED4E6BF301739B28C5C13C0000000000000044000408109F4EAE0BFB0D5E8FACB1914C00000000000000440002DA4B8CFD2DBBFB0D5E8FACB1914C00000000000000440
second_floor	\N	0.0443731523340138781	475	\N	\N	01020000A034BF0D00020000000092B9B7F7D5E7BF80CB21856B3C13C000000000000004408034FF4EEED4E6BF301739B28C5C13C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lP	0.512835680985825326	476	\N	\N	01020000A034BF0D000200000080F5B51E2CD5F0BFE088E89125971DC000000000000004408003FADFAE0FE6BFF04B3A66D0231CC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.680433642555001938	477	\N	\N	01020000A034BF0D0002000000004C1A109A22E93F28897F828FFD20C00000000000000440004C1A109A22E93F8095376C5B421FC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lQ	2.47172150532520174	478	\N	\N	01020000A034BF0D00040000004069437C6A810CC060D06649BBDE2CC000000000000004404069437C6A810CC050F7975167FB2DC000000000000004404069437C6A810CC0309D3316886B2EC00000000000000440207863FE4CE802C0BCCCD5BAE76830C00000000000000440
second_floor	\N	0.257445718287996783	479	\N	\N	01020000A034BF0D00020000004069437C6A810CC0C8BA8D5CEB5A2CC000000000000004404069437C6A810CC060D06649BBDE2CC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.91313261121472822	480	\N	\N	01020000A034BF0D000600000080DCB2204E8804C0F0C85F011B9E27C00000000000000440E05CDC2E214303C0D868D53D66EF27C00000000000000440E05CDC2E214303C0F0161D1FE10328C000000000000004404069437C6A810CC008DA767273532AC000000000000004404069437C6A810CC0D8935C543F3E2BC000000000000004404069437C6A810CC0C8BA8D5CEB5A2CC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lQ	0.49045160207700178	481	\N	\N	01020000A034BF0D0002000000207863FE4CE802C0BCCCD5BAE76830C00000000000000440207863FE4CE802C0C4FD4CF775E630C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lQ	2.19819636366508453	482	\N	\N	01020000A034BF0D0003000000207863FE4CE802C0C4FD4CF775E630C00000000000000440800ABFD434D6ECBF747473F0CD5C32C00000000000000440802FA1F870ABE8BF747473F0CD5C32C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lQ	0.764264763208236775	483	\N	\N	01020000A034BF0D0003000000207863FE4CE802C0C4FD4CF775E630C0000000000000044040C6E66CB0FC02C088671D6502E930C0000000000000044040C6E66CB0FC02C0FC189D930EA931C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lQ	3.64489919105270133	484	\N	\N	01020000A034BF0D000200000040C6E66CB0FC02C0FC189D930EA931C0000000000000044040C6E66CB0FC02C0C4E2A3B0264E35C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lQ	0.174547963211470591	485	\N	\N	01020000A034BF0D000300000040C6E66CB0FC02C0C4E2A3B0264E35C00000000000000440E0DC705854D902C0EC9F3233925235C0000000000000044000CA6284DCA501C0EC9F3233925235C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lQ	0.287546116162318677	486	\N	\N	01020000A034BF0D000500000040C6E66CB0FC02C0C4E2A3B0264E35C00000000000000440C0BCDF82F46203C094016333EF5A35C00000000000000440C0BCDF82F46203C0508E7B114A5C35C00000000000000440E0BDD788106302C02C8EBC90467C35C00000000000000440E0BDD788106302C0AC98E401388535C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lD	1.79809885877850206	487	\N	\N	01020000A034BF0D00030000006050BBD74E5A12C0FC189D930EA931C00000000000000440409E1DE8A69314C0FC189D930EA931C00000000000000440400781AB8F8B19C0FC189D930EA931C00000000000000440
second_floor	\N	0.250000000000483169	488	\N	\N	01020000A034BF0D0002000000404EBBD74E5A11C0FC189D930EA931C000000000000004406050BBD74E5A12C0FC189D930EA931C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lQ	1.96480800630050112	489	\N	\N	01020000A034BF0D000300000040C6E66CB0FC02C0FC189D930EA931C00000000000000440C000B28EED410EC0FC189D930EA931C00000000000000440404EBBD74E5A11C0FC189D930EA931C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lD	1.92035734862469099	490	\N	\N	01020000A034BF0D0002000000400781AB8F8B19C0FC189D930EA931C00000000000000440400781AB8F8B19C0EC12A61DAB9433C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048l7	1.27613336202120209	491	\N	\N	01020000A034BF0D0004000000F05DA33F68DE20C0A4D0749DE5AC35C0000000000000044050C2DE1EB8AB21C0A4D0749DE5AC35C0000000000000044030243411B0CE21C0A4D0749DE5AC35C00000000000000440308A991BCBF222C0A483A722F33E36C00000000000000440
second_floor	\N	0.249999999999488409	492	\N	\N	01020000A034BF0D0002000000105FA33F685E20C0A4D0749DE5AC35C00000000000000440F05DA33F68DE20C0A4D0749DE5AC35C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lD	3.67725346733186065	493	\N	\N	01020000A034BF0D0005000000400781AB8F8B19C0EC12A61DAB9433C00000000000000440400781AB8F8B19C0F0130479B94E35C0000000000000044010FA433D40041BC0A4D0749DE5AC35C0000000000000044050F5CFC030221FC0A4D0749DE5AC35C00000000000000440105FA33F685E20C0A4D0749DE5AC35C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048l7	2.02896715623166379	494	\N	\N	01020000A034BF0D0006000000308A991BCBF222C0A483A722F33E36C0000000000000044028CE986A3C7223C0A483A722F33E36C00000000000000440488ADD50167623C0ACE1C915E04036C00000000000000440F097B627E37826C0ACE1C915E04036C00000000000000440F8CABD00F07D26C0244846A9593E36C00000000000000440F8CABD00F0FD26C0244846A9593E36C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048l7	1.21357020913911451	495	\N	\N	01020000A034BF0D0002000000308A991BCBF222C0A483A722F33E36C0000000000000044078B7711D6F3B21C0FC6CBB21A11A37C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048l0	3.52797968789575611	496	\N	\N	01020000A034BF0D0007000000F05DA33F68DE20C0EC12A61DAB9433C0000000000000044050C2DE1EB8AB21C0EC12A61DAB9433C00000000000000440F8B832025EC721C0EC12A61DAB9433C000000000000004409051437018B822C0385FAE54080D34C00000000000000440E08CC814B4EA26C0385FAE54080D34C0000000000000044018418B45642427C054B90F6DE02934C00000000000000440D84014EA1F7127C054B90F6DE02934C00000000000000440
second_floor	\N	0.249999999999488409	497	\N	\N	01020000A034BF0D0002000000105FA33F685E20C0EC12A61DAB9433C00000000000000440F05DA33F68DE20C0EC12A61DAB9433C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lD	1.79809885877850206	498	\N	\N	01020000A034BF0D0003000000400781AB8F8B19C0EC12A61DAB9433C0000000000000044050F5CFC030221FC0EC12A61DAB9433C00000000000000440105FA33F685E20C0EC12A61DAB9433C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.32877713142249831	499	\N	\N	01020000A034BF0D000300000070B4213EB5C014C0B00C467B70462CC0000000000000044070B4213EB5C014C0C0E51473C4292BC0000000000000044070B4213EB5C014C0F0C85F011B9E27C00000000000000440
second_floor	\N	0.0928257648554620118	500	\N	\N	01020000A034BF0D000200000070B4213EB5C014C0409C1657F7752CC0000000000000044070B4213EB5C014C0B00C467B70462CC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lD	3.92624478699333679	501	\N	\N	01020000A034BF0D0005000000400781AB8F8B19C0FC189D930EA931C00000000000000440400781AB8F8B19C0D8BB7CE04B0730C0000000000000044070B4213EB5C014C048CE498A2AA92DC0000000000000044070B4213EB5C014C030C3475FA3922DC0000000000000044070B4213EB5C014C0409C1657F7752CC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lQ	2.16480328800760979	502	\N	\N	01020000A034BF0D0005000000207863FE4CE802C0BCCCD5BAE76830C000000000000004400001287750F0FFBFCCDD7B22E30A30C0000000000000044040D91CD0328AFDBFCCDD7B22E30A30C0000000000000044000A6F784CA9EF4BFFC302EA7999930C00000000000000440004CEF09953DE9BFFC302EA7991931C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	10.1474003306424478	503	\N	\N	01020000A034BF0D000300000060347A8B256C17C0F0C85F011B9E27C00000000000000440301A9ED3BD9619C008D64DDDCE8826C00000000000000440301A9ED3BD9619C0407B8399F92BFEBF0000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.0403556115579419838	504	\N	\N	01020000A034BF0D0002000000301A9ED3BD9619C0407B8399F92BFEBF0000000000000440301A9ED3BD9619C0C0DB85ACAD86FDBF0000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.0774638183925731028	505	\N	\N	01020000A034BF0D0002000000301A9ED3BD9619C0C0DB85ACAD86FDBF0000000000000440301A9ED3BD9619C0C0F21BF96249FCBF0000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048ie	3.28566286245995709	506	\N	\N	01020000A034BF0D00050000006079F527AB7011C0C0DB85ACAD86FDBF00000000000004404061FDD216AC0FC0C0DB85ACAD86FDBF0000000000000440A01447DF18D70EC0C0DB85ACAD86FDBF0000000000000440808F772C8C7A0AC080D1E64694CDF4BF000000000000044000C3E64694CDF4BF80D1E64694CDF4BF0000000000000440
second_floor	\N	0.249999999999801048	507	\N	\N	01020000A034BF0D00020000008078F527AB7012C0C0DB85ACAD86FDBF00000000000004406079F527AB7011C0C0DB85ACAD86FDBF0000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.78718059746499591	508	\N	\N	01020000A034BF0D0003000000301A9ED3BD9619C0C0DB85ACAD86FDBF000000000000044030416CE64A0B14C0C0DB85ACAD86FDBF00000000000004408078F527AB7012C0C0DB85ACAD86FDBF0000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048il	3.35773400212494488	509	\N	\N	01020000A034BF0D0007000000F05DA33F68DE20C0407B8399F92BFEBF000000000000044050C2DE1EB8AB21C0407B8399F92BFEBF0000000000000440B0A684BA7CCC21C0407B8399F92BFEBF000000000000044048A3049220FD22C0C09683DDDAA6F4BF000000000000044090438D362AB326C0C09683DDDAA6F4BF0000000000000440509860EFAACC26C080F0E816D5DAF3BF00000000000004401079B440D10C27C080F0E816D5DAF3BF0000000000000440
second_floor	\N	0.25	510	\N	\N	01020000A034BF0D0002000000F05DA33F685E20C0407B8399F92BFEBF0000000000000440F05DA33F68DE20C0407B8399F92BFEBF0000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.78718059746499591	511	\N	\N	01020000A034BF0D0003000000301A9ED3BD9619C0407B8399F92BFEBF000000000000044010F3CFC030221FC0407B8399F92BFEBF0000000000000440F05DA33F685E20C0407B8399F92BFEBF0000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.760524743047258811	512	\N	\N	01020000A034BF0D0003000000F8788019788324C0D8EDB5F420A327C0000000000000044050A4B0C2940825C03019E69D3D2828C0000000000000044050A4B0C2940825C0909B9E7061F128C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.65972356744519622	513	\N	\N	01020000A034BF0D000500000070E5CB16888E29C0A0C8AB774CA125C0000000000000044020389449CFE02AC0F075E344054F24C0000000000000044020389449CFE02AC07863B274DEBE21C00000000000000440F00461169C2D2BC0A896E5A7117221C00000000000000440F00461169C2D2BC010E0328373FB20C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.68677859038749034	514	\N	\N	01020000A034BF0D0002000000F00461169C2D2BC010E0328373FB20C00000000000000440F00461169C2D2BC080856023A4371FC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.33441322148874097	515	\N	\N	01020000A034BF0D00030000001865BD4E9F1129C010E0328373FB20C000000000000004409882DED5B52A28C010E0328373FB20C00000000000000440D84F6758E4EA26C0500EA35738771FC00000000000000440
second_floor	\N	0.249970558235915519	516	\N	\N	01020000A034BF0D00020000003091D6729B9129C010E0328373FB20C000000000000004401865BD4E9F1129C010E0328373FB20C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.804692373896500612	517	\N	\N	01020000A034BF0D0003000000F00461169C2D2BC010E0328373FB20C00000000000000440288FABEB84782AC010E0328373FB20C000000000000004403091D6729B9129C010E0328373FB20C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.84658593531987258	518	\N	\N	01020000A034BF0D0004000000D84F6758E4EA26C0500EA35738771FC0000000000000044048145ABFDAEA26C0500EA35738771FC000000000000004408069BC8F9B9126C0F8316F5BDB1420C00000000000000440A85F773F685E23C0F8316F5BDB1420C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048iY	0.729643968321006531	519	\N	\N	01020000A034BF0D0003000000D84F6758E4EA26C0500EA35738771FC000000000000004409855AADD187827C0A04CBA77D45C1EC00000000000000440C81ADF741A7827C060D6707B0C011DC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.00397283970075257	520	\N	\N	01020000A034BF0D0003000000C81ADF741A7827C060D6707B0C011DC00000000000000440C00D375098E327C0103C93B3142A1CC000000000000004401084D38C95E328C040325D3A1A2A1AC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.63891211182687013	521	\N	\N	01020000A034BF0D0004000000C81ADF741A7827C060D6707B0C011DC00000000000000440E0FCB6D1F14427C0809A2035BB9A1CC00000000000000440E0FCB6D1F14427C0203070B2579A17C0000000000000044028A17C8670EB26C0B078FB1B55E716C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048iY	0.429973598563549331	522	\N	\N	01020000A034BF0D000200000028A17C8670EB26C0B078FB1B55E716C0000000000000044088AE9C064B0F26C0B078FB1B55E716C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.04999999600188687	523	\N	\N	01020000A034BF0D000300000088AE9C064B0F26C0B078FB1B55E716C0000000000000044050773460860225C0B078FB1B55E716C00000000000000440E06C256DB1F523C0B078FB1B55E716C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048ia	0.944950908845351822	524	\N	\N	01020000A034BF0D0005000000E06C256DB1F523C0F0F826E7590B13C00000000000000440E06C256DB1F523C03030B028BA7011C00000000000000440E06C256DB1F523C0502EEA7BC41F11C00000000000000440C06C256DB1F523C0102EEA7BC41F11C00000000000000440C06C256DB1F523C0606A3F6271870EC00000000000000440
second_floor	\N	0.0899999999996197175	525	\N	\N	01020000A034BF0D0002000000E06C256DB1F523C0A086E9DC826713C00000000000000440E06C256DB1F523C0F0F826E7590B13C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048iY	0.874825463743505338	526	\N	\N	01020000A034BF0D0003000000E06C256DB1F523C0B078FB1B55E716C00000000000000440E06C256DB1F523C0604F609B220215C00000000000000440E06C256DB1F523C0A086E9DC826713C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048iX	0.953872625850570866	527	\N	\N	01020000A034BF0D000500000088E0DC5CA2C321C0F0F826E7590B13C0000000000000044088E0DC5CA2C321C03030B028BA7011C0000000000000044088E0DC5CA2C321C060F6B3ACE54011C000000000000004406090243E1DD821C0B09624EAEF1711C000000000000004406090243E1DD821C02099CA851A970EC00000000000000440
second_floor	\N	0.0899999999996197175	528	\N	\N	01020000A034BF0D000200000088E0DC5CA2C321C0A086E9DC826713C0000000000000044088E0DC5CA2C321C0F0F826E7590B13C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.72239760869136704	529	\N	\N	01020000A034BF0D0006000000E06C256DB1F523C0B078FB1B55E716C000000000000004406064167ADCE822C0B078FB1B55E716C00000000000000440F8562C5F519E22C0B078FB1B55E716C0000000000000044088E0DC5CA2C321C0D08B5C17F73115C0000000000000044088E0DC5CA2C321C0604F609B220215C0000000000000044088E0DC5CA2C321C0A086E9DC826713C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048ix	0.945075263554304601	530	\N	\N	01020000A034BF0D000500000088AE9C064B0F26C0F0F826E7590B13C0000000000000044088AE9C064B0F26C03030B028BA7011C0000000000000044088AE9C064B0F26C020D03715E51F11C00000000000000440A0AE9C064B0F26C0F0CF3715E51F11C00000000000000440A0AE9C064B0F26C0A026A42F30870EC00000000000000440
second_floor	\N	0.0899999999996197175	531	\N	\N	01020000A034BF0D000200000088AE9C064B0F26C0A086E9DC826713C0000000000000044088AE9C064B0F26C0F0F826E7590B13C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048iY	0.874825463743505338	532	\N	\N	01020000A034BF0D000300000088AE9C064B0F26C0B078FB1B55E716C0000000000000044088AE9C064B0F26C0604F609B220215C0000000000000044088AE9C064B0F26C0A086E9DC826713C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048i_	0.0226459209316883375	533	\N	\N	01020000A034BF0D0002000000307CAFA8562828C050F726E7590B13C0000000000000044078DEA186893028C0C032422BF4FA12C00000000000000440
second_floor	\N	0.116738465468237254	534	\N	\N	01020000A034BF0D0003000000280AB6A6490728C0A086E9DC826713C00000000000000440280AB6A6490728C070DB19EB734D13C00000000000000440307CAFA8562828C050F726E7590B13C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048iY	1.10446169916671755	535	\N	\N	01020000A034BF0D000400000028A17C8670EB26C0B078FB1B55E716C0000000000000044030E804AD0F1C27C0A0EAEACE168616C00000000000000440280AB6A6490728C0B0A688DBA2AF14C00000000000000440280AB6A6490728C0A086E9DC826713C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048i_	1.04118803574269925	536	\N	\N	01020000A034BF0D000700000078DEA186893028C0C032422BF4FA12C0000000000000044078DEA186893028C0902EB028BA7011C0000000000000044078DEA186893028C000E1E53F5B4811C00000000000000440D0FA5B62912228C0B0195AF76A2C11C00000000000000440D0FA5B62912228C0E02249BDDC8C0EC00000000000000440700AB2397E0228C06061A11A900C0EC00000000000000440700AB2397E0228C0A0D1B7C8D7ED0DC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048iY	0.24801179887113603	537	\N	\N	01020000A034BF0D0003000000688875DFD06628C0A086E9DC826713C00000000000000440A065A92255B228C0104151638BFE13C00000000000000440688C0E9784C628C0104151638BFE13C00000000000000440
second_floor	\N	0.127279220613563282	538	\N	\N	01020000A034BF0D0002000000C0409464BC3828C050F726E7590B13C00000000000000440688875DFD06628C0A086E9DC826713C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048i_	0.0226459209316883375	539	\N	\N	01020000A034BF0D000200000078DEA186893028C0C032422BF4FA12C00000000000000440C0409464BC3828C050F726E7590B13C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6Mn	3.95391621922730296	540	\N	\N	01020000A034BF0D000B00000024B4F1A7B3A030C058FCC28A664523C0000000000000044024B4F1A7B3A030C080F72720617622C000000000000004404C0E56E392A030C0D8ABF0961F7622C000000000000004404C0E56E392A030C01821C90BFC2822C000000000000004405CA3AC8A093630C0304B765AE95321C000000000000004405CA3AC8A093630C0908D8457D85620C000000000000004407000FB90840330C0708F42C89CE31FC000000000000004407000FB90840330C0E0D47EF7372A1CC000000000000004407000FB90840330C070C8F88AEC7018C000000000000004408C8EDE26AF0F30C000906A33424018C000000000000004408C8EDE26AF0F30C0B048466494D217C00000000000000440
second_floor	\N	0.114707788247997655	541	\N	\N	01020000A034BF0D000200000024B4F1A7B3A030C0A03A7185218023C0000000000000044024B4F1A7B3A030C058FCC28A664523C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144698998	542	\N	\N	01020000A034BF0D000300000024B4F1A7B3A030C058D009A2F9CC25C0000000000000044024B4F1A7B3A030C09061A28DCD9C24C0000000000000044024B4F1A7B3A030C0A03A7185218023C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6Mo	3.9177370883842153	543	\N	\N	01020000A034BF0D0006000000302A3BB525F332C058FCC28A664523C00000000000000440302A3BB525F332C080F72720617622C0000000000000044010849FF004F332C040ABF0961F7622C0000000000000044010849FF004F332C0A821C90BFC2822C0000000000000044098083048866332C0B82AEABAFE0921C0000000000000044098083048866332C06036261400CD17C00000000000000440
second_floor	\N	0.114707788247997655	544	\N	\N	01020000A034BF0D0002000000302A3BB525F332C0A03A7185218023C00000000000000440302A3BB525F332C058FCC28A664523C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144698998	545	\N	\N	01020000A034BF0D0003000000302A3BB525F332C058D009A2F9CC25C00000000000000440302A3BB525F332C09061A28DCD9C24C00000000000000440302A3BB525F332C0A03A7185218023C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6Mo	0.794829018554867983	546	\N	\N	01020000A034BF0D000300000098083048866332C06036261400CD17C00000000000000440885684B57FF232C0A0FED45E1A9115C00000000000000440885684B57FF232C0B06683A6FB8B15C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6Mo	0.111689468351547194	547	\N	\N	01020000A034BF0D000200000098083048866332C06036261400CD17C00000000000000440D0CE647C4E4F32C0404FF9E4207C17C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.16324328044452718	548	\N	\N	01020000A034BF0D00040000001478CFF27D8134C038747ADF03A427C00000000000000440DC63433B30FD32C0A89C924E9FAC2AC00000000000000440DC63433B30FD32C098166E11F1B32AC00000000000000440F458A3AC7DFC32C0682CAE2E56B52AC00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6MC	1.69813226291298269	549	\N	\N	01020000A034BF0D0004000000686D51F45E5732C0682CAE2E56B52AC00000000000000440F0D938F008C931C0682CAE2E56B52AC000000000000004401CB5326F732531C0682CAE2E56B52AC00000000000000440C4AFACCE5FCA30C01837BA6F7D6B2BC00000000000000440
second_floor	\N	0.0944491311510091691	550	\N	\N	01020000A034BF0D000200000048DBCAC58C6F32C0682CAE2E56B52AC00000000000000440686D51F45E5732C0682CAE2E56B52AC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.550550868849015274	551	\N	\N	01020000A034BF0D0002000000F458A3AC7DFC32C0682CAE2E56B52AC0000000000000044048DBCAC58C6F32C0682CAE2E56B52AC00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6MC	3.54203926811741532	552	\N	\N	01020000A034BF0D0007000000C4AFACCE5FCA30C01837BA6F7D6B2BC00000000000000440C4AFACCE5FCA30C0C8F3256190EA2BC00000000000000440C4AFACCE5FCA30C0B87BFA75BE1530C00000000000000440184A7CB3739830C064E12A91AA4730C00000000000000440184A7CB3739830C0D4E153D3DAFE30C0000000000000044000A8FA86D2A330C0BC3FD2A6390A31C0000000000000044000A8FA86D2A330C0C4DA1D681E2731C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6MC	1.32802359982341156	553	\N	\N	01020000A034BF0D0003000000C4AFACCE5FCA30C01837BA6F7D6B2BC0000000000000044068D549BB932030C06082F448E5172AC000000000000004402014D20977792FC06082F448E5172AC00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6MB	3.65988953173157849	554	\N	\N	01020000A034BF0D000A000000F458A3AC7DFC32C0608DBFFA29042CC00000000000000440F458A3AC7DFC32C058925A652FD32CC00000000000000440D4FE3E719EFC32C018DE91EE70D32CC00000000000000440D4FE3E719EFC32C08868B97994202DC00000000000000440D0410410800F34C080EE43B757462FC00000000000000440D0410410800F34C0A4EE972ED62930C00000000000000440208CD6DFB02F34C0F4386AFE064A30C00000000000000440208CD6DFB02F34C090437A93A7FC30C0000000000000044088D2DABDB12234C028FD75B5A60931C0000000000000044088D2DABDB12234C0E4DE5B49622631C00000000000000440
second_floor	\N	0.117704428251997228	555	\N	\N	01020000A034BF0D0002000000F458A3AC7DFC32C0C8AD8339E6C72BC00000000000000440F458A3AC7DFC32C0608DBFFA29042CC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.536255205691020365	556	\N	\N	01020000A034BF0D0002000000F458A3AC7DFC32C0682CAE2E56B52AC00000000000000440F458A3AC7DFC32C0C8AD8339E6C72BC00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6M6	3.67388455316772999	557	\N	\N	01020000A034BF0D000A000000FC6B4EE547FD38C0608DBFFA29042CC00000000000000440FC6B4EE547FD38C058925A652FD32CC000000000000004400CC6B22027FD38C038DE91EE70D32CC000000000000004400CC6B22027FD38C06868B97994202DC00000000000000440C4DF0774C6EA37C0F8340FD355452FC00000000000000440C4DF0774C6EA37C0E0917D3C552930C0000000000000044034AFC595AFC937C070C2BF1A6C4A30C0000000000000044034AFC595AFC937C014BA247742FC30C00000000000000440180A78BB91D737C0F814D79C240A31C00000000000000440180A78BB91D737C0B0C2E58C6F2931C00000000000000440
second_floor	\N	0.117704428251997228	558	\N	\N	01020000A034BF0D0002000000FC6B4EE547FD38C0C8AD8339E6C72BC00000000000000440FC6B4EE547FD38C0608DBFFA29042CC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.07008630144699168	559	\N	\N	01020000A034BF0D0003000000FC6B4EE547FD38C038747ADF03A427C00000000000000440FC6B4EE547FD38C0D88652313AAB2AC00000000000000440FC6B4EE547FD38C0C8AD8339E6C72BC00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6M5	3.67268547063345041	560	\N	\N	01020000A034BF0D000A000000309F81187B303AC0608DBFFA29042CC00000000000000440309F81187B303AC050925A652FD32CC0000000000000044004451DDD9B303AC0F8DD91EE70D32CC0000000000000044004451DDD9B303AC0A868B97994202DC000000000000004402C2BC889FC423BC0F8340FD355452FC000000000000004402C2BC889FC423BC0AC8F3A933E2130C000000000000004409C68D260A0633BC01CCD446AE24130C000000000000004409C68D260A0633BC04407D6ABDEFC30C000000000000004400C429E7125563BC0D42D0A9B590A31C000000000000004400C429E7125563BC07C819F5D7B2931C00000000000000440
second_floor	\N	0.117704428251997228	561	\N	\N	01020000A034BF0D0002000000309F81187B303AC0C8AD8339E6C72BC00000000000000440309F81187B303AC0608DBFFA29042CC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.07008630144699168	562	\N	\N	01020000A034BF0D0003000000309F81187B303AC038747ADF03A427C00000000000000440309F81187B303AC0D88652313AAB2AC00000000000000440309F81187B303AC0C8AD8339E6C72BC00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6M0	5.76126341087317506	563	\N	\N	01020000A034BF0D000B0000004856D4771B3C3DC0D842A7C82A9F2AC00000000000000440C0E9EC7B71CA3DC0D842A7C82A9F2AC0000000000000044020D7F92095D33DC0D842A7C82A9F2AC0000000000000044074B87435431B3EC02880B19FCE0F2AC00000000000000440BCFA29CD535C3EC02880B19FCE0F2AC0000000000000044064C9F15F461D3FC0781D41C5B3912BC0000000000000044064C9F15F461D3FC0B4EC7AF7C22030C00000000000000440F48BE788A2FC3EC0242A85CE664130C00000000000000440F48BE788A2FC3EC03CAA95475AFD30C00000000000000440DC7961E1080A3FC024980FA0C00A31C00000000000000440DC7961E1080A3FC0CCEBA462E22931C00000000000000440
second_floor	\N	0.0990523598810000294	564	\N	\N	01020000A034BF0D0002000000780EFEF8BF223DC0D842A7C82A9F2AC000000000000004404856D4771B3C3DC0D842A7C82A9F2AC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.68748455667194364	565	\N	\N	01020000A034BF0D0004000000AC71F9CBCE103BC038747ADF03A427C0000000000000044000D98F40628E3CC0D842A7C82A9F2AC00000000000000440007BE5F469943CC0D842A7C82A9F2AC00000000000000440780EFEF8BF223DC0D842A7C82A9F2AC00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6M_	3.95726694323858164	566	\N	\N	01020000A034BF0D000A000000F45BF6C287593BC058FCC28A664523C00000000000000440F45BF6C287593BC068F72720617622C0000000000000044094019287A8593BC028ACF0961F7622C0000000000000044094019287A8593BC0A820C90BFC2822C00000000000000440B45C0C5092D73BC0606AD47A282D21C00000000000000440B45C0C5092D73BC0D8253B53C13020C00000000000000440249A162736F83BC0F0554D4AF3DE1FC00000000000000440249A162736F83BC0B0D96A2B337818C0000000000000044094A7D685D1EA3BC0700F6BA6A04218C0000000000000044094A7D685D1EA3BC090E27A6BA9D317C00000000000000440
second_floor	\N	0.114707788247997655	567	\N	\N	01020000A034BF0D0002000000F45BF6C287593BC0A03A7185218023C00000000000000440F45BF6C287593BC058FCC28A664523C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.78601396263049139	568	\N	\N	01020000A034BF0D0003000000F45BF6C287593BC0A89F80F1911227C00000000000000440F45BF6C287593BC09061A28DCD9C24C00000000000000440F45BF6C287593BC0A03A7185218023C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6MV	1.99243655854302282	569	\N	\N	01020000A034BF0D0004000000A28CEF4DD9CA40C0D0BB70247F5128C00000000000000440A28CEF4DD9CA40C0C0E2A12C2B6E29C00000000000000440A28CEF4DD9CA40C038B299800ED429C00000000000000440720A1B4CD93A41C078A947790E942BC00000000000000440
second_floor	\N	0.108744794309004078	570	\N	\N	01020000A034BF0D0002000000A28CEF4DD9CA40C01866A2BED11928C00000000000000440A28CEF4DD9CA40C0D0BB70247F5128C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.15008630144700419	571	\N	\N	01020000A034BF0D0003000000A28CEF4DD9CA40C058D009A2F9CC25C00000000000000440A28CEF4DD9CA40C0283F71B625FD26C00000000000000440A28CEF4DD9CA40C01866A2BED11928C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6MV	3.4454310311275278	572	\N	\N	01020000A034BF0D0006000000720A1B4CD93A41C078A947790E942BC00000000000000440720A1B4CD93A41C0509291EF562C30C000000000000004402A29A0372B4B41C0C0CF9BC6FA4C30C000000000000004402A29A0372B4B41C0E8ED011B56FC30C00000000000000440E8F91B995E4441C06C4C0A58EF0931C00000000000000440E8F91B995E4441C0D81530EDE72831C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6MQ	5.66938160823340276	573	\N	\N	01020000A034BF0D000B000000A46DE562C63742C02893DB4C143F2AC0000000000000044060B7F164F17E42C02893DB4C143F2AC00000000000000440CCC97425BCA042C02893DB4C143F2AC00000000000000440A2763AE9F3A942C0C8DFC43D351A2AC00000000000000440A69B727477CA42C0C8DFC43D351A2AC0000000000000044096BD8BFFAB2843C08867296A07932BC0000000000000044096BD8BFFAB2843C058710268D32B30C00000000000000440DE9E06145A1843C0C8AE0C3F774C30C00000000000000440DE9E06145A1843C0E00E91A2D9FC30C00000000000000440DA795919FE1E43C0D8C436AD210A31C00000000000000440DA795919FE1E43C0D0F470F0612A31C00000000000000440
second_floor	\N	0.0900000000000034106	574	\N	\N	01020000A034BF0D0002000000B81B2D44412C42C02893DB4C143F2AC00000000000000440A46DE562C63742C02893DB4C143F2AC00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6MV	2.22149827801891142	575	\N	\N	01020000A034BF0D0006000000720A1B4CD93A41C078A947790E942BC00000000000000440DEBCFB9A4F9941C0C8DFC43D351A2AC00000000000000440BA12D8BD13BA41C0C8DFC43D351A2AC0000000000000044090BF9D814BC341C02893DB4C143F2AC00000000000000440FCD1204216E541C02893DB4C143F2AC00000000000000440B81B2D44412C42C02893DB4C143F2AC00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6MP	5.74862458177883262	576	\N	\N	01020000A034BF0D000B00000050B5C6DDDAC545C01097699D8F9B2AC00000000000000440966BBADBAF7E45C01097699D8F9B2AC00000000000000440EEFCA758EF7345C01097699D8F9B2AC00000000000000440B63D180CA35345C0389A2A6B5E1A2AC0000000000000044012E30B9CC43245C0389A2A6B5E1A2AC000000000000004408E4AB6CEC7D444C048FC80A051922BC000000000000004408E4AB6CEC7D444C020F693B0A12B30C0000000000000044046693BBA19E544C090339E87454C30C0000000000000044046693BBA19E544C030CED4B45DFD30C000000000000004402AE29E425CDE44C068DC0DA4D80A31C000000000000004402AE29E425CDE44C0B082D8B9EF2A31C00000000000000440
second_floor	\N	0.0900000000000034106	577	\N	\N	01020000A034BF0D00020000003C077FFC5FD145C01097699D8F9B2AC0000000000000044050B5C6DDDAC545C01097699D8F9B2AC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.70214075262370335	578	\N	\N	01020000A034BF0D000400000046C63E9D2FDE46C0C836700860B327C00000000000000440326E00B8232446C01097699D8F9B2AC00000000000000440F6508BFE8A1846C01097699D8F9B2AC000000000000004403C077FFC5FD145C01097699D8F9B2AC00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6MK	3.64089571896671815	579	\N	\N	01020000A034BF0D000A000000EADD226D9D4B47C0C8AB17E570162CC00000000000000440EADD226D9D4B47C0D0B0B24F76E52CC00000000000000440220BD50A8D4B47C0E8FBE9D8B7E52CC00000000000000440220BD50A8D4B47C0A0871164DB322DC00000000000000440CA548D7238C246C0086130C52D582FC00000000000000440CA548D7238C246C0843098E2162C30C0000000000000044012360887E6B146C0F46DA2B9BA4C30C0000000000000044012360887E6B146C0CC93D082E8FC30C0000000000000044032B942B399B846C00C9A45DB4E0A31C0000000000000044032B942B399B846C0544010F1652A31C00000000000000440
second_floor	\N	0.0934017198709966578	580	\N	\N	01020000A034BF0D0002000000EADD226D9D4B47C0E8326F8B9EE62BC00000000000000440EADD226D9D4B47C0C8AB17E570162CC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.10008630144699282	581	\N	\N	01020000A034BF0D0003000000EADD226D9D4B47C0C836700860B327C00000000000000440EADD226D9D4B47C0F80B3E83F2C92AC00000000000000440EADD226D9D4B47C0E8326F8B9EE62BC00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6MJ	3.64240924473739858	582	\N	\N	01020000A034BF0D000A0000008277BC0637E547C0C8AB17E570162CC000000000000004408277BC0637E547C0C8B0B24F76E52CC00000000000000440A24A0A6947E547C050FDE9D8B7E52CC00000000000000440A24A0A6947E547C030861164DB322DC00000000000000440F6FDCC43626E48C078531CCF46572FC00000000000000440F6FDCC43626E48C01C8D9326C92B30C00000000000000440AE1C522FB47E48C08CCA9DFD6C4C30C00000000000000440AE1C522FB47E48C044244A2B85FD30C00000000000000440B60B1BDCF57748C03446B8D1010B31C00000000000000440B60B1BDCF57748C0CC6213BAEF2A31C00000000000000440
second_floor	\N	0.0934017198709966578	583	\N	\N	01020000A034BF0D00020000008277BC0637E547C0E8326F8B9EE62BC000000000000004408277BC0637E547C0C8AB17E570162CC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.10008630144699282	584	\N	\N	01020000A034BF0D00030000008277BC0637E547C0C836700860B327C000000000000004408277BC0637E547C0F80B3E83F2C92AC000000000000004408277BC0637E547C0E8326F8B9EE62BC00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6LL	3.96223703471859023	585	\N	\N	01020000A034BF0D000A000000FA74D8DA927948C058FCC28A664523C00000000000000440FA74D8DA927948C058F72720617622C00000000000000440EA47263DA37948C090ABF0961F7622C00000000000000440EA47263DA37948C03021C90BFC2822C00000000000000440C6E8C20A97B848C0C89D56D52C2D21C00000000000000440C6E8C20A97B848C0B84686E1B53120C00000000000000440820748F6E8C848C09097E366DCE01FC00000000000000440820748F6E8C848C030D088741F7A18C00000000000000440FE5F79CA37C248C010941316964418C00000000000000440FE5F79CA37C248C01072AF248BCE17C00000000000000440
second_floor	\N	0.114707788247997655	586	\N	\N	01020000A034BF0D0002000000FA74D8DA927948C0A03A7185218023C00000000000000440FA74D8DA927948C058FCC28A664523C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.10008630144700703	587	\N	\N	01020000A034BF0D0003000000FA74D8DA927948C0C836700860B327C00000000000000440FA74D8DA927948C09061A28DCD9C24C00000000000000440FA74D8DA927948C0A03A7185218023C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.09845406209645358	588	\N	\N	01020000A034BF0D00020000006AA776C5A31E4AC0C836700860B327C000000000000004402A89E0F291DC4AC0D0BD17BE18AB2AC00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6Nk	0.431801161535688593	589	\N	\N	01020000A034BF0D00030000001A4A73B5BFE44AC0C8AB17E570162CC000000000000004401A4A73B5BFE44AC0101D24A83FF12CC00000000000000440BEA46EA426E54AC0A0871164DBF22CC00000000000000440
second_floor	\N	0.0934017198709966578	590	\N	\N	01020000A034BF0D00020000001A4A73B5BFE44AC0E8326F8B9EE62BC000000000000004401A4A73B5BFE44AC0C8AB17E570162CC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.642721995200796981	591	\N	\N	01020000A034BF0D00030000002A89E0F291DC4AC0D0BD17BE18AB2AC000000000000004401A4A73B5BFE44AC088C162C8CFCB2AC000000000000004401A4A73B5BFE44AC0E8326F8B9EE62BC00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6Nk	3.21016691692983347	592	\N	\N	01020000A034BF0D0008000000BEA46EA426E54AC0A0871164DBF22CC00000000000000440BEA46EA426E54AC0B8871164DB322DC000000000000004403208A4E7D25B4AC0E8F93B572A582FC000000000000004403208A4E7D25B4AC05460A3EA3A2C30C000000000000004407AE91EFC804B4AC0C49DADC1DE4C30C000000000000004407AE91EFC804B4AC00C513A6713FD30C00000000000000440C2E2BE4C33524AC09C437A08780A31C00000000000000440C2E2BE4C33524AC03460D5F0652A31C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6Nk	0.0191456334580311534	593	\N	\N	01020000A034BF0D0003000000BEA46EA426E54AC0A0871164DBF22CC000000000000004403A96D315CBE64AC0B8C17D9E49EC2CC00000000000000440BA3B6FDAEBE64AC0B8C17D9E49EC2CC00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6Ng	1.71837064130224659	594	\N	\N	01020000A034BF0D0004000000A26DE562C6374BC0D0BD17BE18AB2AC000000000000004405AB7F164F17E4BC0D0BD17BE18AB2AC000000000000004407A8B80D1D8CA4BC0D0BD17BE18AB2AC00000000000000440762D136861FE4BC0C84562183B792BC00000000000000440
second_floor	\N	0.0962825636510160621	595	\N	\N	01020000A034BF0D000200000072663666732B4BC0D0BD17BE18AB2AC00000000000000440A26DE562C6374BC0D0BD17BE18AB2AC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	0.61625520413014101	596	\N	\N	01020000A034BF0D00030000002A89E0F291DC4AC0D0BD17BE18AB2AC00000000000000440BA1C2A6448E44AC0D0BD17BE18AB2AC0000000000000044072663666732B4BC0D0BD17BE18AB2AC00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6Ng	3.51831646826663524	597	\N	\N	01020000A034BF0D0007000000762D136861FE4BC0C84562183B792BC00000000000000440762D136861FE4BC030127E4BD7FC2BC00000000000000440762D136861FE4BC0F8CB9704C01830C000000000000004400AA44F8178154CC020B91037EE4630C000000000000004400AA44F8178154CC034BCE4E7580331C000000000000004405AFB95758F114CC0940D58FF2A0B31C000000000000004405AFB95758F114CC0B4B650BAEF2A31C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6Ng	1.25591647231050341	598	\N	\N	01020000A034BF0D0003000000762D136861FE4BC0C84562183B792BC000000000000004406AA98D355A544CC0F05578E257212AC00000000000000440AA55D6EE867B4CC0F05578E257212AC00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6LM	3.9843687642332446	599	\N	\N	01020000A034BF0D00090000002230B0040C4E4AC058FCC28A664523C000000000000004402230B0040C4E4AC068D59182BA2822C000000000000004402230B0040C4E4AC018955C24001F22C00000000000000440964B9AF18B114AC0E80205D8FF2C21C00000000000000440964B9AF18B114AC0D8AB34E4883120C00000000000000440DE2C15063A014AC0F061406C82E01FC00000000000000440DE2C15063A014AC0D0052C6F797A18C000000000000004409A8F1D7EF9074AC0F0EFE8AE7D4418C000000000000004409A8F1D7EF9074AC0303E9B6BBAAF17C00000000000000440
second_floor	\N	0.114707788247997655	600	\N	\N	01020000A034BF0D00020000002230B0040C4E4AC0A03A7185218023C000000000000004402230B0040C4E4AC058FCC28A664523C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.72971743634536779	601	\N	\N	01020000A034BF0D00030000002230B0040C4E4AC0E0138A0BBFF526C000000000000004402230B0040C4E4AC09061A28DCD9C24C000000000000004402230B0040C4E4AC0A03A7185218023C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6LR	3.95334153263834187	602	\N	\N	01020000A034BF0D000600000076BF72FA34EA4AC030FCC28A664523C0000000000000044076BF72FA34EA4AC050F72720617622C000000000000004408292C05C45EA4AC020ABF0961F7622C000000000000004408292C05C45EA4AC07021C90BFC2822C000000000000004401EEC2CE1E2314BC000BB17FA850A21C000000000000004401EEC2CE1E2314BC020EE8F8B1AA817C00000000000000440
second_floor	\N	0.114707788248068709	603	\N	\N	01020000A034BF0D000200000076BF72FA34EA4AC0A03A7185218023C0000000000000044076BF72FA34EA4AC030FCC28A664523C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.17008630144700021	604	\N	\N	01020000A034BF0D000300000076BF72FA34EA4AC068A7AD1237D725C0000000000000044076BF72FA34EA4AC09061A28DCD9C24C0000000000000044076BF72FA34EA4AC0A03A7185218023C00000000000000440
second_floor	1BUg4a4jr0B9Q5NnDgB6LS	3.9861568793049007	605	\N	\N	01020000A034BF0D000B000000F6B180612A134CC058FCC28A664523C00000000000000440F6B180612A134CC050F72720617622C00000000000000440FE84CEC33A134CC030ABF0961F7622C00000000000000440FE84CEC33A134CC08821C90BFC2822C00000000000000440AAF902A295484CC0D84EF792905321C00000000000000440AAF902A295484CC018FCB31F715820C0000000000000044036DD9DC291614CC0D0DB903A01E91FC0000000000000044036DD9DC291614CC00015E8FE66611AC0000000000000044036DD9DC291614CC0D0C63FE94A7318C0000000000000044082157E5AD05B4CC0308941A83F4518C0000000000000044082157E5AD05B4CC030A5A91DDBAF17C00000000000000440
second_floor	\N	0.114707788247997655	606	\N	\N	01020000A034BF0D0002000000F6B180612A134CC0A03A7185218023C00000000000000440F6B180612A134CC058FCC28A664523C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	1.17008630144700021	607	\N	\N	01020000A034BF0D0003000000F6B180612A134CC068A7AD1237D725C00000000000000440F6B180612A134CC09061A28DCD9C24C00000000000000440F6B180612A134CC0A03A7185218023C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lE	1.03168724842709159	608	\N	\N	01020000A034BF0D0003000000D24212692D984DC0880F09DE84662AC0000000000000044012BF4DABE0564DC08800F7E6516129C00000000000000440729D11BACC3A4DC0087A062202F128C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lE	2.45202655902118671	609	\N	\N	01020000A034BF0D0006000000D24212692D984DC070E450AF8FAB2AC000000000000004408E0842B888974DC080CD917222AE2AC000000000000004408E0842B888974DC0686545C1E0E32BC000000000000004408E0842B888974DC0B8169694658F2CC000000000000004408E0842B888974DC0A09878F413172DC000000000000004408E0842B888974DC078166ED7EE912FC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lE	0.700130196159255425	610	\N	\N	01020000A034BF0D00020000008E0842B888974DC078166ED7EE912FC000000000000004400A67A82029584DC0B0DD0EA2B14730C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ048lE	0.749438712518126215	611	\N	\N	01020000A034BF0D00020000008E0842B888974DC078166ED7EE912FC0000000000000044022E5763D5CDB4DC0FC31A1C8A35030C00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.71181754123300323	612	\N	\N	01020000A034BF0D0002000000005EA33F689E22C0108FFE4D940F2DC00000000000000440005EA33F689E22C0D8EDB5F420A327C00000000000000440
second_floor	\N	3.88723068316779363	613	\N	\N	01020000A034BF0D0003000000F87D8A907CF124C05807A30C40F631C00000000000000440005EA33F689E22C08048698C39D92DC00000000000000440005EA33F689E22C0108FFE4D940F2DC00000000000000440
second_floor	1mWTVVwiXDHQKYjSZ04A3D	2.77678287975999183	614	\N	\N	01020000A034BF0D00020000003B548F320E5451C088FDF44BA63D2DC000000000000004403B548F320E5451C0A8AAA3CFEFAF27C00000000000000440
second_floor	\N	3.69828326745999147	615	\N	\N	01020000A034BF0D000300000089855B35799E51C044E93BEB08DE31C000000000000004403B548F320E5451C07823582DC9962DC000000000000004403B548F320E5451C088FDF44BA63D2DC00000000000000440
\.


--
-- Data for Name: second_floor_edges_vertices_pgr; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.second_floor_edges_vertices_pgr (id, cnt, chk, ein, eout, the_geom) FROM stdin;
1	\N	\N	\N	\N	0101000020E6100000B6E54859BBC451C0097868E10B2F4540
2	\N	\N	\N	\N	0101000020E61000008C0019C6B9C451C0FAB69E370E2F4540
3	\N	\N	\N	\N	0101000020E610000078891CC6B9C451C0FF7D749D0E2F4540
4	\N	\N	\N	\N	0101000020E61000007C446C32BAC451C08F8BC8BD112F4540
5	\N	\N	\N	\N	0101000020E61000006AA48B32BAC451C00F0C4944152F4540
6	\N	\N	\N	\N	0101000020E610000081B66532BAC451C0F2E13C01112F4540
7	\N	\N	\N	\N	0101000020E61000006416A366BBC451C0371015AC152F4540
8	\N	\N	\N	\N	0101000020E6100000B9F79508C3C451C0D18833A9122F4540
9	\N	\N	\N	\N	0101000020E6100000A59E88F2C6C451C0B9F9E3A8122F4540
10	\N	\N	\N	\N	0101000020E6100000C417FF54CAC451C03DBFA39C122F4540
11	\N	\N	\N	\N	0101000020E61000000CE0242BCCC451C06F822F89FB2E4540
12	\N	\N	\N	\N	0101000020E6100000B7EC8DF1CDC451C044962A8AFA2E4540
13	\N	\N	\N	\N	0101000020E6100000F30CD9ABCBC451C09DDB3989FB2E4540
14	\N	\N	\N	\N	0101000020E610000073EDB854CAC451C079DB0F280B2F4540
15	\N	\N	\N	\N	0101000020E61000008937BE54CAC451C005BCF0B70B2F4540
16	\N	\N	\N	\N	0101000020E6100000DFE707D1D3C451C0B0F941DCFC2E4540
17	\N	\N	\N	\N	0101000020E6100000534755AACCC451C0ACC010A5F82E4540
18	\N	\N	\N	\N	0101000020E6100000EE0C8AE9CDC451C03030599C122F4540
19	\N	\N	\N	\N	0101000020E610000044AFA8AECFC451C060FF339C122F4540
20	\N	\N	\N	\N	0101000020E610000056F78C45D0C451C08BF6F66F102F4540
21	\N	\N	\N	\N	0101000020E6100000A61A9AD2D2C451C047030CAB122F4540
22	\N	\N	\N	\N	0101000020E6100000EBB6AD41D6C451C050C9DDD50D2F4540
23	\N	\N	\N	\N	0101000020E6100000FD206941D6C451C0A7B054D4062F4540
24	\N	\N	\N	\N	0101000020E6100000D70D92BFD7C451C07E96BDD50D2F4540
25	\N	\N	\N	\N	0101000020E61000007244F7F5D8C451C0994DA3D50D2F4540
26	\N	\N	\N	\N	0101000020E6100000A4E5BA4CD6C451C0B13B757B1C2F4540
27	\N	\N	\N	\N	0101000020E6100000FECFCD4CD6C451C04C1A066A1E2F4540
28	\N	\N	\N	\N	0101000020E61000005D679354D4C451C00B829F7B1C2F4540
29	\N	\N	\N	\N	0101000020E6100000E7B38DD0D1C451C0815EA5D31D2F4540
30	\N	\N	\N	\N	0101000020E61000007DBFDFD3D4C451C0F3DB947B1C2F4540
31	\N	\N	\N	\N	0101000020E610000099E26DB1CEC451C09A46E7D31D2F4540
32	\N	\N	\N	\N	0101000020E6100000961768BDD2C451C00461B3A71F2F4540
33	\N	\N	\N	\N	0101000020E6100000A5244D60D3C451C0D9EB2E99202F4540
34	\N	\N	\N	\N	0101000020E6100000DA08B931D2C451C0B5480FB3242F4540
35	\N	\N	\N	\N	0101000020E6100000411E184AD1C451C02D7B22B3242F4540
36	\N	\N	\N	\N	0101000020E61000004B877033CFC451C01B934EB3242F4540
37	\N	\N	\N	\N	0101000020E610000015C28B33CFC451C0549E028C272F4540
38	\N	\N	\N	\N	0101000020E6100000C8BAA533CFC451C0E3530A432A2F4540
39	\N	\N	\N	\N	0101000020E6100000EA378933CFC451C0E9320B48272F4540
40	\N	\N	\N	\N	0101000020E6100000A462240BCDC451C02DDB2F8C272F4540
41	\N	\N	\N	\N	0101000020E6100000287C9C1FCDC451C0C26A18472A2F4540
42	\N	\N	\N	\N	0101000020E61000001FDD210BCDC451C0C46F3848272F4540
43	\N	\N	\N	\N	0101000020E61000005189334AD1C451C05B86D68B272F4540
44	\N	\N	\N	\N	0101000020E61000000FB04D4AD1C451C0E83BDE422A2F4540
45	\N	\N	\N	\N	0101000020E6100000A5FA304AD1C451C0F21ADF47272F4540
46	\N	\N	\N	\N	0101000020E6100000122F0A6DD3C451C0F7B0B147272F4540
47	\N	\N	\N	\N	0101000020E6100000BBFB2B75D3C451C055D5BF53272F4540
48	\N	\N	\N	\N	0101000020E610000071DE4C7DD3C451C00656B047272F4540
49	\N	\N	\N	\N	0101000020E6100000BD191FF3D3C451C014E043B6262F4540
50	\N	\N	\N	\N	0101000020E61000001A1A2E75D3C451C0EB6EA88B272F4540
51	\N	\N	\N	\N	0101000020E61000006844EA60D3C451C051029E422A2F4540
52	\N	\N	\N	\N	0101000020E61000003C76F113C8C451C0571C00981C2F4540
53	\N	\N	\N	\N	0101000020E6100000EBD95008C3C451C0DBD1BD210B2F4540
54	\N	\N	\N	\N	0101000020E6100000793B331AC0C451C0931B1954052F4540
55	\N	\N	\N	\N	0101000020E610000011425608C3C451C096F485B80B2F4540
56	\N	\N	\N	\N	0101000020E61000000D0A121AC0C451C0576F145D022F4540
57	\N	\N	\N	\N	0101000020E61000003A65ACA7BCC451C020534E4CFD2E4540
58	\N	\N	\N	\N	0101000020E6100000EA54722FC0C451C08BB46D97FD2E4540
59	\N	\N	\N	\N	0101000020E6100000D2AFB808BFC451C0C7F1796D062F4540
60	\N	\N	\N	\N	0101000020E61000007C60FBC6B9C451C08812DA851C2F4540
61	\N	\N	\N	\N	0101000020E61000001C4579E0BBC451C0D0E1B0851C2F4540
62	\N	\N	\N	\N	0101000020E61000002AD14067BEC451C0BA37BDE41D2F4540
63	\N	\N	\N	\N	0101000020E6100000599D6D63BBC451C0087EBA851C2F4540
64	\N	\N	\N	\N	0101000020E610000070FA0E81C1C451C0A5467FE41D2F4540
65	\N	\N	\N	\N	0101000020E6100000CFDEE27CBDC451C0817AA4B51F2F4540
66	\N	\N	\N	\N	0101000020E610000067A72CF7BDC451C0C12733C8242F4540
67	\N	\N	\N	\N	0101000020E6100000A3F2DDF5BEC451C081621FC8242F4540
68	\N	\N	\N	\N	0101000020E6100000108B850CC1C451C058A8F5C7242F4540
69	\N	\N	\N	\N	0101000020E610000068C8DE2FC3C451C009B788A0272F4540
70	\N	\N	\N	\N	0101000020E61000007DF5991BC3C451C0DAA7FB622A2F4540
71	\N	\N	\N	\N	0101000020E61000002358DC2FC3C451C09A4B915C272F4540
72	\N	\N	\N	\N	0101000020E6100000177F9F0CC1C451C078BDB3A0272F4540
73	\N	\N	\N	\N	0101000020E6100000B13EB80CC1C451C07BBE9C572A2F4540
74	\N	\N	\N	\N	0101000020E61000006E139D0CC1C451C00A52BC5C272F4540
75	\N	\N	\N	\N	0101000020E610000064B6F7F5BEC451C0A477DDA0272F4540
76	\N	\N	\N	\N	0101000020E6100000F54710F6BEC451C0AF78C6572A2F4540
77	\N	\N	\N	\N	0101000020E61000003C4FF5F5BEC451C0380CE65C272F4540
78	\N	\N	\N	\N	0101000020E610000005029EF2BCC451C0636605A1272F4540
79	\N	\N	\N	\N	0101000020E6100000E86C63DABCC451C0A10F7F502A2F4540
80	\N	\N	\N	\N	0101000020E6100000349F9BF2BCC451C0F5FA0D5D272F4540
81	\N	\N	\N	\N	0101000020E6100000C5F931DFBCC451C04ACB9B9F202F4540
82	\N	\N	\N	\N	0101000020E610000022980AC7B9C451C09D413C3C1E2F4540
83	\N	\N	\N	\N	0101000020E6100000C28ED5BAB3C451C0BD86A557152F4540
84	\N	\N	\N	\N	0101000020E61000004C30841DAFC451C03F07FD57152F4540
85	\N	\N	\N	\N	0101000020E6100000F4A13FB0ACC451C0EBB08AB1132F4540
86	\N	\N	\N	\N	0101000020E610000096C69FF3ABC451C08021E699122F4540
87	\N	\N	\N	\N	0101000020E610000003209A68A5C451C029365E9A122F4540
88	\N	\N	\N	\N	0101000020E61000003D746C1AA3C451C02FCF879A122F4540
89	\N	\N	\N	\N	0101000020E610000009BC47CBA0C451C0741AB19A122F4540
90	\N	\N	\N	\N	0101000020E6100000A99D7CCBA0C451C069634423192F4540
91	\N	\N	\N	\N	0101000020E610000076E9FAE8A1C451C0B44EDB06242F4540
92	\N	\N	\N	\N	0101000020E610000085E079CBA0C451C07E49A4CC182F4540
93	\N	\N	\N	\N	0101000020E6100000072665B7A0C451C0667CB29A122F4540
94	\N	\N	\N	\N	0101000020E6100000FFCA14049FC451C0C4A5D09A122F4540
95	\N	\N	\N	\N	0101000020E6100000E3AA47689EC451C06EFCF781132F4540
96	\N	\N	\N	\N	0101000020E6100000CDD074689EC451C03EAE6E23192F4540
97	\N	\N	\N	\N	0101000020E6100000CF80D8479DC451C0F7D98901242F4540
98	\N	\N	\N	\N	0101000020E6100000381A72689EC451C05394CECC182F4540
99	\N	\N	\N	\N	0101000020E6100000C911B8C298C451C09C6EAA68152F4540
100	\N	\N	\N	\N	0101000020E61000004851D5C298C451C01128D123192F4540
101	\N	\N	\N	\N	0101000020E6100000BEFD7B3F99C451C096B61890252F4540
102	\N	\N	\N	\N	0101000020E610000039AAD2C298C451C0240E31CD182F4540
103	\N	\N	\N	\N	0101000020E61000006B76323590C451C083583B69152F4540
104	\N	\N	\N	\N	0101000020E6100000CAB24E3590C451C010126224192F4540
105	\N	\N	\N	\N	0101000020E6100000A721261D90C451C0096A4048222F4540
106	\N	\N	\N	\N	0101000020E61000003A234C3590C451C022F8C1CD182F4540
107	\N	\N	\N	\N	0101000020E6100000AE8E81D888C451C040FFB369152F4540
108	\N	\N	\N	\N	0101000020E610000000EC9CD888C451C0E0B8DA24192F4540
109	\N	\N	\N	\N	0101000020E61000003F183EBE88C451C00FB0B54C222F4540
110	\N	\N	\N	\N	0101000020E6100000AA709AD888C451C0EE9E3ACE182F4540
111	\N	\N	\N	\N	0101000020E6100000B986F3D886C451C0B017D469152F4540
112	\N	\N	\N	\N	0101000020E6100000B0A7101880C451C0BC803E6A152F4540
113	\N	\N	\N	\N	0101000020E6100000DBFB2A1880C451C0743A6525192F4540
114	\N	\N	\N	\N	0101000020E610000095ECB61184C451C0505DF5AD252F4540
115	\N	\N	\N	\N	0101000020E61000009198281880C451C08120C5CE182F4540
116	\N	\N	\N	\N	0101000020E6100000345614727AC451C07320578A132F4540
117	\N	\N	\N	\N	0101000020E6100000ACF568E179C451C0ECD5D8B3122F4540
118	\N	\N	\N	\N	0101000020E610000054CF372378C451C0A706F3B3122F4540
119	\N	\N	\N	\N	0101000020E61000007D42070F78C451C0BF34F4B3122F4540
120	\N	\N	\N	\N	0101000020E6100000DD18330F78C451C0CCAFDF25192F4540
121	\N	\N	\N	\N	0101000020E6100000EDE756F276C451C02178D405242F4540
122	\N	\N	\N	\N	0101000020E6100000A7CB300F78C451C0D6953FCF182F4540
123	\N	\N	\N	\N	0101000020E6100000FE7E30C075C451C0478C16B4122F4540
124	\N	\N	\N	\N	0101000020E610000058DAB47173C451C0767F38B4122F4540
125	\N	\N	\N	\N	0101000020E610000038BFDF7173C451C096FA2326192F4540
126	\N	\N	\N	\N	0101000020E6100000464E345172C451C069CF7400242F4540
127	\N	\N	\N	\N	0101000020E6100000B17EDD7173C451C0A1E083CF182F4540
128	\N	\N	\N	\N	0101000020E6100000BA5735D56CC451C074C097B4122F4540
129	\N	\N	\N	\N	0101000020E6100000B914F21F6CC451C034B780C1132F4540
130	\N	\N	\N	\N	0101000020E610000085BB14206CC451C05C418D26192F4540
131	\N	\N	\N	\N	0101000020E6100000BF2A52416DC451C0E2607E04242F4540
132	\N	\N	\N	\N	0101000020E61000001A8F12206CC451C06427EDCF182F4540
133	\N	\N	\N	\N	0101000020E6100000503FF5BC69C451C0FE0C886B152F4540
134	\N	\N	\N	\N	0101000020E6100000CADA961E65C451C0B8C9C76B152F4540
135	\N	\N	\N	\N	0101000020E6100000B21389765DC451C0A9059AAC152F4540
136	\N	\N	\N	\N	0101000020E61000000B157D7258C451C073F5F8B6122F4540
137	\N	\N	\N	\N	0101000020E61000007FA0169056C451C0ADDE10B7122F4540
138	\N	\N	\N	\N	0101000020E6100000486575B14FC451C03AADCEBE122F4540
139	\N	\N	\N	\N	0101000020E6100000E9469D5D4EC451C099BCDEBE122F4540
140	\N	\N	\N	\N	0101000020E6100000B7C2B32649C451C072A11CBF122F4540
141	\N	\N	\N	\N	0101000020E6100000275F137C42C451C04021C2851C2F4540
142	\N	\N	\N	\N	0101000020E6100000C39A808844C451C060FEAA851C2F4540
143	\N	\N	\N	\N	0101000020E6100000A3A99EFE46C451C0C09DD5D31D2F4540
144	\N	\N	\N	\N	0101000020E61000005642340944C451C0F8A2B0851C2F4540
145	\N	\N	\N	\N	0101000020E6100000CCB310424AC451C0F497AFD31D2F4540
146	\N	\N	\N	\N	0101000020E610000038F0CA2346C451C0544B82C21F2F4540
147	\N	\N	\N	\N	0101000020E6100000753910B546C451C088BEBCAB242F4540
148	\N	\N	\N	\N	0101000020E6100000C720D48E47C451C00AECB2AB242F4540
149	\N	\N	\N	\N	0101000020E6100000CEB77BA549C451C0AD979AAB242F4540
150	\N	\N	\N	\N	0101000020E6100000DA1871D44BC451C01B6A6391272F4540
151	\N	\N	\N	\N	0101000020E61000008EDB21C04BC451C0B9815B552A2F4540
152	\N	\N	\N	\N	0101000020E6100000E8A96FD44BC451C096FE6B4D272F4540
153	\N	\N	\N	\N	0101000020E6100000CC298BA549C451C02D2C7D91272F4540
154	\N	\N	\N	\N	0101000020E6100000A7059AA549C451C08587335B2A2F4540
155	\N	\N	\N	\N	0101000020E610000090BF89A549C451C0A9C0854D272F4540
156	\N	\N	\N	\N	0101000020E61000009F61E38E47C451C08D809591272F4540
157	\N	\N	\N	\N	0101000020E6100000320EF28E47C451C0E6DB4B5B2A2F4540
158	\N	\N	\N	\N	0101000020E6100000E2FBE18E47C451C009159E4D272F4540
159	\N	\N	\N	\N	0101000020E6100000562DC49545C451C0BBC9B44D272F4540
160	\N	\N	\N	\N	0101000020E61000001249898745C451C0215B6765272F4540
161	\N	\N	\N	\N	0101000020E61000003E2F8A8745C451C006D8AC91272F4540
162	\N	\N	\N	\N	0101000020E610000010D3237C45C451C0437919612A2F4540
163	\N	\N	\N	\N	0101000020E61000001ABE8E7745C451C02923B64D272F4540
164	\N	\N	\N	\N	0101000020E61000003BA49BE944C451C099632BC2262F4540
165	\N	\N	\N	\N	0101000020E6100000D76D2A6B45C451C0799B64D4202F4540
166	\N	\N	\N	\N	0101000020E61000000D9D1D7C42C451C08F419C871E2F4540
167	\N	\N	\N	\N	0101000020E6100000446104224BC451C0F9C3BDFF0A2F4540
168	\N	\N	\N	\N	0101000020E610000003A0FDBE48C451C0EDE18A2C052F4540
169	\N	\N	\N	\N	0101000020E6100000987608224BC451C0E4F328C20B2F4540
170	\N	\N	\N	\N	0101000020E6100000A5F4F5BE48C451C0EA6129BA032F4540
171	\N	\N	\N	\N	0101000020E6100000EA39FE9345C451C0C8E3036AFF2E4540
172	\N	\N	\N	\N	0101000020E610000086C1FBC348C451C00A661D7C012F4540
173	\N	\N	\N	\N	0101000020E6100000C7C0C2C348C451C012378CBBF62E4540
174	\N	\N	\N	\N	0101000020E61000002033866E48C451C07B3686AEF62E4540
175	\N	\N	\N	\N	0101000020E6100000CC808D9D48C451C0C8C81B19F62E4540
176	\N	\N	\N	\N	0101000020E6100000E7B0BB2B4DC451C0395AE97B012F4540
177	\N	\N	\N	\N	0101000020E6100000E8E34CBF50C451C0531ABE7B012F4540
178	\N	\N	\N	\N	0101000020E6100000A8C56FAC4CC451C0864BEF7B012F4540
179	\N	\N	\N	\N	0101000020E61000005F6C2DBF50C451C0914F85D1FB2E4540
180	\N	\N	\N	\N	0101000020E61000003AB0E6D154C451C04D1E7CA3F52E4540
181	\N	\N	\N	\N	0101000020E6100000C31652E356C451C03F7589F4F32E4540
182	\N	\N	\N	\N	0101000020E6100000D2F49A5254C451C08A5382A3F52E4540
183	\N	\N	\N	\N	0101000020E6100000B9F8C4E85AC451C062C71AF6F32E4540
184	\N	\N	\N	\N	0101000020E6100000F689522E55C451C03081946CF12E4540
185	\N	\N	\N	\N	0101000020E61000002FCF09D254C451C008F652D1FB2E4540
186	\N	\N	\N	\N	0101000020E610000086C8765B5BC451C0C32AD818FA2E4540
187	\N	\N	\N	\N	0101000020E6100000D2FABD5254C451C0452B59D1FB2E4540
188	\N	\N	\N	\N	0101000020E6100000D8A2775D4EC451C00D7137E00B2F4540
189	\N	\N	\N	\N	0101000020E6100000C022765D4EC451C000B91D9A0B2F4540
190	\N	\N	\N	\N	0101000020E61000001700279D45C451C05AEF7123032F4540
191	\N	\N	\N	\N	0101000020E6100000CDA0DEC550C451C06CA57C04302F4540
192	\N	\N	\N	\N	0101000020E61000001E4ADFC550C451C07C78F622302F4540
193	\N	\N	\N	\N	0101000020E6100000218FE0C550C451C0134F765D302F4540
194	\N	\N	\N	\N	0101000020E610000085638BB84CC451C04E692723302F4540
195	\N	\N	\N	\N	0101000020E610000005D583A246C451C0C9B126BF312F4540
196	\N	\N	\N	\N	0101000020E6100000240BD8374DC451C090772123302F4540
197	\N	\N	\N	\N	0101000020E61000006F8332D354C451C05C8F4A04302F4540
198	\N	\N	\N	\N	0101000020E6100000E181FDF85AC451C0F787EFEA312F4540
199	\N	\N	\N	\N	0101000020E61000004EDCE55354C451C0A6C45004302F4540
200	\N	\N	\N	\N	0101000020E61000009D8DD3F658C451C0D6A3EFC9102F4540
201	\N	\N	\N	\N	0101000020E610000075567F135FC451C0FD3881871C2F4540
202	\N	\N	\N	\N	0101000020E61000002D838B135FC451C053FF258E1E2F4540
203	\N	\N	\N	\N	0101000020E6100000367578FA5CC451C0B8CB9C871C2F4540
204	\N	\N	\N	\N	0101000020E6100000D04CCDD65AC451C054F1795F1E2F4540
205	\N	\N	\N	\N	0101000020E61000002AF7C0795DC451C0CD4996871C2F4540
206	\N	\N	\N	\N	0101000020E61000003923494F57C451C06B4304DC1D2F4540
207	\N	\N	\N	\N	0101000020E610000065F147635BC451C0CD8A3030202F4540
208	\N	\N	\N	\N	0101000020E61000005278D1CC5CC451C014943A48222F4540
209	\N	\N	\N	\N	0101000020E610000019CF7DD75AC451C05515F5AF242F4540
210	\N	\N	\N	\N	0101000020E610000033138DFC59C451C0EA1B00B0242F4540
211	\N	\N	\N	\N	0101000020E6100000EE7BE5E557C451C0C6D11AB0242F4540
212	\N	\N	\N	\N	0101000020E61000009AF0F5E557C451C08586B988272F4540
213	\N	\N	\N	\N	0101000020E6100000850E06E657C451C062F155522A2F4540
214	\N	\N	\N	\N	0101000020E6100000A367F4E557C451C0041BC244272F4540
215	\N	\N	\N	\N	0101000020E610000006FEFAB655C451C03220D588272F4540
216	\N	\N	\N	\N	0101000020E61000000EF568CB55C451C0D834AA4C2A2F4540
217	\N	\N	\N	\N	0101000020E6100000C479F9B655C451C0B0B4DD44272F4540
218	\N	\N	\N	\N	0101000020E610000024B89DFC59C451C0A6D09E88272F4540
219	\N	\N	\N	\N	0101000020E6100000E205AEFC59C451C0044653522A2F4540
220	\N	\N	\N	\N	0101000020E6100000AD2A9CFC59C451C02365A744272F4540
221	\N	\N	\N	\N	0101000020E6100000584FB8125CC451C00BD48388272F4540
222	\N	\N	\N	\N	0101000020E6100000CCF5DF1A5CC451C0792C9B94272F4540
223	\N	\N	\N	\N	0101000020E6100000AA13D8F15BC451C0F5138E44272F4540
224	\N	\N	\N	\N	0101000020E610000038B926ED5BC451C070ACC58A2A2F4540
225	\N	\N	\N	\N	0101000020E61000009E58D9505CC451C0C63F8944272F4540
226	\N	\N	\N	\N	0101000020E61000001D4904B05CC451C05AF321D5262F4540
227	\N	\N	\N	\N	0101000020E6100000310D07235CC451C0E2FF8288272F4540
228	\N	\N	\N	\N	0101000020E6100000B5FDAD1E65C451C0B183EE26192F4540
229	\N	\N	\N	\N	0101000020E6100000431C7FFE63C451C0DF36FE01242F4540
230	\N	\N	\N	\N	0101000020E61000008AE4AB1E65C451C0B9694ED0182F4540
231	\N	\N	\N	\N	0101000020E61000002AEE0CBD69C451C0EDC6AE26192F4540
232	\N	\N	\N	\N	0101000020E610000034FCA59F68C451C0E60BDC05242F4540
233	\N	\N	\N	\N	0101000020E61000004EC80ABD69C451C0F5AC0ED0182F4540
234	\N	\N	\N	\N	0101000020E6100000994F12BC69C451C0B50457AF252F4540
235	\N	\N	\N	\N	0101000020E61000003A94707768C451C0107C8241242F4540
236	\N	\N	\N	\N	0101000020E6100000B5F85CCF69C451C0FB736F2E0E2F4540
237	\N	\N	\N	\N	0101000020E6100000CC9FEF8668C451C02A50812E0E2F4540
238	\N	\N	\N	\N	0101000020E61000002EA0467165C451C0773500220D2F4540
239	\N	\N	\N	\N	0101000020E6100000674D07B768C451C07AB47E2E0E2F4540
240	\N	\N	\N	\N	0101000020E61000000472592465C451C0FD8C05FA022F4540
241	\N	\N	\N	\N	0101000020E6100000EB01005963C451C050A800170F2F4540
242	\N	\N	\N	\N	0101000020E6100000D4B850CF69C451C05A7493400C2F4540
243	\N	\N	\N	\N	0101000020E61000009C4B42186CC451C085F7CFFB022F4540
244	\N	\N	\N	\N	0101000020E61000003FED52CF69C451C07AE376990C2F4540
245	\N	\N	\N	\N	0101000020E6100000461205C075C451C0B0B8E73F0C2F4540
246	\N	\N	\N	\N	0101000020E6100000887A947773C451C0224165F2022F4540
247	\N	\N	\N	\N	0101000020E61000005C6807C075C451C0CD27CB980C2F4540
248	\N	\N	\N	\N	0101000020E610000087E50B2378C451C01933C43F0C2F4540
249	\N	\N	\N	\N	0101000020E61000005F16E76A7AC451C0BCF5DAF1022F4540
250	\N	\N	\N	\N	0101000020E610000057420E2378C451C036A2A7980C2F4540
251	\N	\N	\N	\N	0101000020E61000004469CB317EC451C0B14AF74D0E2F4540
252	\N	\N	\N	\N	0101000020E6100000152143C881C451C0D3C639F0022F4540
253	\N	\N	\N	\N	0101000020E6100000A6B05BFF7DC451C07B52FA4D0E2F4540
254	\N	\N	\N	\N	0101000020E610000018E63A727AC451C0BEC7BB25192F4540
255	\N	\N	\N	\N	0101000020E6100000D47C81937BC451C00ABBDEFF232F4540
256	\N	\N	\N	\N	0101000020E6100000549238727AC451C0C9AD1BCF182F4540
257	\N	\N	\N	\N	0101000020E6100000B886D8D886C451C06E2B2EB3112F4540
258	\N	\N	\N	\N	0101000020E6100000DDE13F9688C451C04B681FE40C2F4540
259	\N	\N	\N	\N	0101000020E6100000D0DBDAD886C451C0F2764D05122F4540
260	\N	\N	\N	\N	0101000020E6100000FEABD6BB88C451C05737AEF2022F4540
261	\N	\N	\N	\N	0101000020E61000001DF274848CC451C089B0CDDA0E2F4540
262	\N	\N	\N	\N	0101000020E6100000C4EDE51B90C451C03A4ADAED022F4540
263	\N	\N	\N	\N	0101000020E61000001738A1568CC451C03F9FD0DA0E2F4540
264	\N	\N	\N	\N	0101000020E61000000F24C7A89AC451C062A576510E2F4540
265	\N	\N	\N	\N	0101000020E6100000F542890F97C451C0AAADC2EB022F4540
266	\N	\N	\N	\N	0101000020E61000004DDD9AD69AC451C0E38873510E2F4540
267	\N	\N	\N	\N	0101000020E6100000D5CA30B7A0C451C0F23836220C2F4540
268	\N	\N	\N	\N	0101000020E6100000F099126E9EC451C0860DD9EC022F4540
269	\N	\N	\N	\N	0101000020E61000008E0533B7A0C451C0EB49BF680C2F4540
270	\N	\N	\N	\N	0101000020E6100000A19B371AA3C451C0C78B0B220C2F4540
271	\N	\N	\N	\N	0101000020E6100000E3F7AD61A5C451C0554DC6EA022F4540
272	\N	\N	\N	\N	0101000020E6100000B2DB391AA3C451C0BD9C94680C2F4540
273	\N	\N	\N	\N	0101000020E610000074F6CF68A5C451C0067FF122192F4540
274	\N	\N	\N	\N	0101000020E6100000CAAE258AA6C451C0785DD700242F4540
275	\N	\N	\N	\N	0101000020E6100000A22CCD68A5C451C01D6551CC182F4540
276	\N	\N	\N	\N	0101000020E6100000D7DB07E7AEC451C029821E390E2F4540
277	\N	\N	\N	\N	0101000020E6100000EC087F07AFC451C08A5630210C2F4540
278	\N	\N	\N	\N	0101000020E6100000ECA70D09AFC451C0E1FB14DC0A2F4540
279	\N	\N	\N	\N	0101000020E6100000AC638107AFC451C07F67B9670C2F4540
280	\N	\N	\N	\N	0101000020E6100000204F37C0ACC451C0AC51D5EB022F4540
281	\N	\N	\N	\N	0101000020E610000060DE1810AFC451C07506C5E50A2F4540
282	\N	\N	\N	\N	0101000020E610000023ECD851B0C451C027D003390E2F4540
283	\N	\N	\N	\N	0101000020E61000005446DE67B3C451C03DA7BE080D2F4540
284	\N	\N	\N	\N	0101000020E61000006C40D220B0C451C0B46D07390E2F4540
285	\N	\N	\N	\N	0101000020E6100000E1ABD2B3B3C451C00C9EBBE9022F4540
286	\N	\N	\N	\N	0101000020E61000003627C659B5C451C0916ED2030F2F4540
287	\N	\N	\N	\N	0101000020E610000043B96DB0ACC451C046B56B22192F4540
288	\N	\N	\N	\N	0101000020E61000003A92099AABC451C059213417242F4540
289	\N	\N	\N	\N	0101000020E610000072DB6AB0ACC451C0609BCBCB182F4540
290	\N	\N	\N	\N	0101000020E61000002F96A41DAFC451C0314A3E22192F4540
291	\N	\N	\N	\N	0101000020E6100000BAE0273BB0C451C098F47C1C242F4540
292	\N	\N	\N	\N	0101000020E6100000B2B1A11DAFC451C04D309ECB182F4540
293	\N	\N	\N	\N	0101000020E6100000A882F6BAB3C451C0A3C9E621192F4540
294	\N	\N	\N	\N	0101000020E6100000DF0F56DCB4C451C072376D16242F4540
295	\N	\N	\N	\N	0101000020E61000007D91F3BAB3C451C0BEAF46CB182F4540
296	\N	\N	\N	\N	0101000020E6100000A3B5B952B8C451C048487BC4102F4540
297	\N	\N	\N	\N	0101000020E6100000F2A249C3B9C451C0EDA676FD062F4540
298	\N	\N	\N	\N	0101000020E610000062CD22C7B8C451C02275B387052F4540
299	\N	\N	\N	\N	0101000020E61000002D430CD1BAC451C0EDCF276D052F4540
300	\N	\N	\N	\N	0101000020E610000002B7E88F56C451C0AD8D25B70A2F4540
301	\N	\N	\N	\N	0101000020E61000009AA97DDF58C451C0D676A197002F4540
302	\N	\N	\N	\N	0101000020E61000005C073CE9CDC451C080555E6B0A2F4540
303	\N	\N	\N	\N	0101000020E6100000AC41F338D0C451C05AC529D7002F4540
\.


--
-- Data for Name: second_floor_rooms; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.second_floor_rooms (level, _area_id, coord_sys, geom) FROM stdin;
second_floor	1mWTVVwiXDHQKYjSZ04A3D	IFC_COORDSYS_0	01030000A034BF0D0001000000400000000010C12DEE49CFBF30857987C5F522C07F256C787AA500408078F527AB7012C030857987C5F522C07F256C787AA500408078F527AB7012C00000A561EDB9933F7F256C787AA50040F05DA33F685E20C00000A561EDB9933F7F256C787AA50040F05DA33F685E20C000CF256ED1FF22C07F256C787AA500403091D6729B9129C000CF256ED1FF22C07F256C787AA500403091D6729B9129C0009E4BDCA2FF1BC07F256C787AA50040B078EBB99CC92CC0009E4BDCA2FF1BC07F256C787AA50040B078EBB99CC92CC0680A704B120E23C07F256C787AA5004010DF512003302CC0680A704B120E23C07F256C787AA5004010DF512003302CC0A03A7185218023C07F256C787AA500405A4FB8383E564DC0A03A7185218023C07F256C787AA500405A4FB8383E564DC0C818DF80EBFA22C07F256C787AA50040F214B94798304DC0C818DF80EBFA22C07F256C787AA50040F214B94798304DC00015E8FE66611CC07F256C787AA5004082D7AE70F4FF4DC00015E8FE66611CC07F256C787AA5004082D7AE70F4FF4DC048009DDB42F322C07F256C787AA5004051A9037F0A2650C048009DDB42F322C07F256C787AA5004051A9037F0A2650C060CD068452B31AC07F256C787AA50040E1AB77E1840A51C060CD068452B31AC07F256C787AA50040E1AB77E1840A51C0A0D26601810323C07F256C787AA50040755CA765853252C0A0D26601810323C07F256C787AA50040755CA765853252C0E06D57D8C8671CC07F256C787AA50040C5030026419152C0E06D57D8C8671CC07F256C787AA50040C5030026419152C0C842B80212F922C07F256C787AA50040BD3BF841548652C0C842B80212F922C07F256C787AA50040BD3BF841548652C0980F85CFDEC528C07F256C787AA50040C9129CB2919052C0980F85CFDEC528C07F256C787AA50040C9129CB2919052C0FCBAF59A229630C07F256C787AA50040C9129CB2913052C0FCBAF59A229630C07F256C787AA50040C9129CB2913052C090D498BCE3472CC07F256C787AA5004061870CE28F2252C090D498BCE3472CC07F256C787AA5004061870CE28F2252C088FDF44BA63D2DC07F256C787AA50040811496C7671D51C088FDF44BA63D2DC07F256C787AA50040811496C7671D51C0A882E09D5E5C2CC07F256C787AA50040AA996999A61E4EC0A882E09D5E5C2CC07F256C787AA50040AA996999A61E4EC090D498BCE34728C07F256C787AA500404233033340F84CC090D498BCE34728C07F256C787AA500404233033340F84CC03014EA9F4C2E28C07F256C787AA5004072663666732B4BC03014EA9F4C2E28C07F256C787AA5004072663666732B4BC0E8326F8B9EE62BC07F256C787AA500403C077FFC5FD145C0E8326F8B9EE62BC07F256C787AA500403C077FFC5FD145C01866A2BED11928C07F256C787AA50040780EFEF8BF223DC01866A2BED11928C07F256C787AA50040780EFEF8BF223DC0C8AD8339E6C72BC07F256C787AA5004048DBCAC58C6F32C0C8AD8339E6C72BC07F256C787AA5004048DBCAC58C6F32C01866A2BED11928C07F256C787AA50040D09710A0C7262DC01866A2BED11928C07F256C787AA50040D09710A0C7262DC040C23181C74228C07F256C787AA50040D09710A0C72629C040C23181C74228C07F256C787AA50040D09710A0C72629C0108FFE4D940F2DC07F256C787AA50040D0B050E561EA20C0108FFE4D940F2DC07F256C787AA50040D0B050E561EA20C0B00C467B70462CC07F256C787AA5004020764F12A54F12C0B00C467B70462CC07F256C787AA5004020764F12A54F12C0C8BA8D5CEB5A2CC07F256C787AA5004000D89C91836FCEBFC8BA8D5CEB5A2CC07F256C787AA5004000D89C91836FCEBF80D912483D1329C07F256C787AA50040008E281DD227F53F80D912483D1329C07F256C787AA50040008E281DD227F53F387CEC74B3F522C07F256C787AA50040006ED2D5D70BF93F387CEC74B3F522C07F256C787AA50040006ED2D5D70BF93F8043C6B8B8231CC07F256C787AA500400000DE473AC2763F8043C6B8B8231CC07F256C787AA500400000DE473AC2763F30857987C5F522C07F256C787AA500400010C12DEE49CFBF30857987C5F522C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048lQ	IFC_COORDSYS_0	01030000A034BF0D0001000000130000000080B7521926DABF50626F0D006033C07F256C787AA500400080B7521926DABF50626F0D00E032C07F256C787AA5004000E846B25A8AD0BF50626F0D00E032C07F256C787AA5004000E846B25A8AD0BF988677D39BD931C07F256C787AA50040009E826AE2DFD8BF988677D39BD931C07F256C787AA50040009E826AE2DFD8BF645344A068A631C07F256C787AA5004000FCAB9CD78ECEBF645344A068A631C07F256C787AA5004000FCAB9CD78ECEBFFC302EA7991931C07F256C787AA5004000FCAB9CD78ECEBFFC302EA7999930C07F256C787AA5004000FCAB9CD78ECEBF60D06649BBDE2CC07F256C787AA50040404EBBD74E5A11C060D06649BBDE2CC07F256C787AA50040404EBBD74E5A11C0486A0E377F4637C07F256C787AA50040604FB3DD6A5A10C0486A0E377F4637C07F256C787AA50040604FB3DD6A5A10C0C87436A8704F37C07F256C787AA50040007423592D45E0BFC87436A8704F37C07F256C787AA50040007423592D45E0BF8CDDF558244537C07F256C787AA5004000E846B25A8AD0BF8CDDF558244537C07F256C787AA5004000E846B25A8AD0BF50626F0D006033C07F256C787AA500400080B7521926DABF50626F0D006033C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048lD	IFC_COORDSYS_0	01030000A034BF0D000100000005000000105FA33F685E20C0409C1657F7752CC07F256C787AA50040105FA33F685E20C0A881F5AD091B37C07F256C787AA500406050BBD74E5A12C0A881F5AD091B37C07F256C787AA500406050BBD74E5A12C0409C1657F7752CC07F256C787AA50040105FA33F685E20C0409C1657F7752CC07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048lf	IFC_COORDSYS_0	01030000A034BF0D00010000000D0000009AA0AEC5EE344EC0747176ECFA5133C07F256C787AA5004002377E00BD314EC0747176ECFA5133C07F256C787AA5004002377E00BD314EC0747176ECFAD132C07F256C787AA500406A2EAB61AB334EC0747176ECFAD132C07F256C787AA500406A2EAB61AB334EC058D846CFFA9131C07F256C787AA5004072B89C2B971E4EC058D846CFFA9131C07F256C787AA5004072B89C2B971E4EC0E849C9C798C22CC07F256C787AA50040A1C234FCB11550C0E849C9C798C22CC07F256C787AA5004039B139CCA71550C0FC9A580047E534C07F256C787AA50040D2553D83853E4EC0381997FB30E534C07F256C787AA50040D2553D83853E4EC0CC8D56ECFA5134C07F256C787AA500409AA0AEC5EE344EC0CC8D56ECFA5134C07F256C787AA500409AA0AEC5EE344EC0747176ECFA5133C07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6MV	IFC_COORDSYS_0	01030000A034BF0D00010000000B000000B81B2D44412C42C0C8031957EBE22BC07F256C787AA50040DCC550217D0B42C0C8031957EBE22BC07F256C787AA50040DCC550217D0B42C0F8364C8A1E162DC07F256C787AA500404C035BF8202C42C0F8364C8A1E162DC07F256C787AA500404C035BF8202C42C02CA2779C41BE32C07F256C787AA50040C8A452BB871E42C02CA2779C41BE32C07F256C787AA50040C8A452BB871E42C00C6B9D313ADD32C07F256C787AA50040084FE576356A40C0286C9D313ADD32C07F256C787AA50040084FE576356A40C0D0BB70247F5128C07F256C787AA50040B81B2D44412C42C0D0BB70247F5128C07F256C787AA50040B81B2D44412C42C0C8031957EBE22BC07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6MQ	IFC_COORDSYS_0	01030000A034BF0D00010000000B000000A8921DEE495842C0F8364C8A1E162DC07F256C787AA50040A8921DEE495842C0C8031957EBE22BC07F256C787AA50040A46DE562C63742C0C8031957EBE22BC07F256C787AA50040A46DE562C63742C0D0BB70247F5128C07F256C787AA5004084E8F9100EF943C0D0BB70247F5128C07F256C787AA5004084E8F9100EF943C024D2B1DF81DE32C07F256C787AA50040300BB921EE4442C024D2B1DF81DE32C07F256C787AA50040300BB921EE4442C02CA2779C41BE32C07F256C787AA5004038551317A63742C02CA2779C41BE32C07F256C787AA5004038551317A63742C0F8364C8A1E162DC07F256C787AA50040A8921DEE495842C0F8364C8A1E162DC07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6MP	IFC_COORDSYS_0	01030000A034BF0D00010000000B00000050B5C6DDDAC545C09878E4B13DE32BC07F256C787AA50040AC5ABA6DFCA445C09878E4B13DE32BC07F256C787AA50040AC5ABA6DFCA445C0C8AB17E570162DC07F256C787AA500401C98C444A0C545C0C8AB17E570162DC07F256C787AA500401C98C444A0C545C0DC2BE7C96ABE32C07F256C787AA50040E4898B5525B845C0DC2BE7C96ABE32C07F256C787AA50040E4898B5525B845C024D2B1DF81DE32C07F256C787AA50040703AB22F930444C024D2B1DF81DE32C07F256C787AA50040703AB22F930444C0D0BB70247F5128C07F256C787AA5004050B5C6DDDAC545C0D0BB70247F5128C07F256C787AA5004050B5C6DDDAC545C09878E4B13DE32BC07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6M0	IFC_COORDSYS_0	01030000A034BF0D00010000000B0000009098890F2C7D3DC0C077254E51012DC07F256C787AA500409098890F2C7D3DC08844F21A1ECE2BC07F256C787AA500404856D4771B3C3DC08844F21A1ECE2BC07F256C787AA500404856D4771B3C3DC0D0BB70247F5128C07F256C787AA500401CFD2C58B05E40C0D0BB70247F5128C07F256C787AA500401CFD2C58B05E40C0286C9D313ADD32C07F256C787AA5004080F96812B1563DC0286C9D313ADD32C07F256C787AA5004080F96812B1563DC08018086F18BE32C07F256C787AA50040B01D7561E43B3DC08018086F18BE32C07F256C787AA50040B01D7561E43B3DC0C077254E51012DC07F256C787AA500409098890F2C7D3DC0C077254E51012DC07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048kN	IFC_COORDSYS_0	01030000A034BF0D00010000000500000039B139CCA72550C0F40CE4D129D234C07F256C787AA50040A1C234FCB12550C08842CD9CEABD2CC07F256C787AA5004039548F320E0C51C08842CD9CEABD2CC07F256C787AA5004039548F320E0C51C0F40CE4D129D234C07F256C787AA5004039B139CCA72550C0F40CE4D129D234C07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6MC	IFC_COORDSYS_0	01030000A034BF0D00010000000C00000040E40F52C17A2EC0287CABA07E112DC07F256C787AA5004040E40F52C17A2EC0F048786D4BDE2BC07F256C787AA50040904D4EE510B32DC0F048786D4BDE2BC07F256C787AA50040904D4EE510B32DC0D0BB70247F5128C07F256C787AA50040686D51F45E5732C0D0BB70247F5128C07F256C787AA50040686D51F45E5732C0C8F3256190EA2BC07F256C787AA50040686D51F45E5732C02CA074D5AADA32C07F256C787AA5004030C547338CE02DC02CA074D5AADA32C07F256C787AA5004030C547338CE02DC024052914C6BD32C07F256C787AA50040904D4EE510B32DC024052914C6BD32C07F256C787AA50040904D4EE510B32DC0287CABA07E112DC07F256C787AA5004040E40F52C17A2EC0287CABA07E112DC07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6Ng	IFC_COORDSYS_0	01030000A034BF0D00010000000C0000008A99892629EC4CC0686545C1E0E32BC07F256C787AA500404AED406DFCC44CC0686545C1E0E32BC07F256C787AA500404AED406DFCC44CC0A09878F413172DC07F256C787AA5004072DAB99F2AF34CC0A09878F413172DC07F256C787AA5004072DAB99F2AF34CC00429B924BDBE32C07F256C787AA500401289468858EB4CC00429B924BDBE32C07F256C787AA500401289468858EB4CC024D2B1DF81DE32C07F256C787AA50040A26DE562C6374BC024D2B1DF81DE32C07F256C787AA50040A26DE562C6374BC030127E4BD7FC2BC07F256C787AA50040A26DE562C6374BC07846AB03CF5E28C07F256C787AA500408A99892629EC4CC07846AB03CF5E28C07F256C787AA500408A99892629EC4CC0686545C1E0E32BC07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048l$	IFC_COORDSYS_0	01030000A034BF0D00010000001300000051A9037F0A1650C030B03E8568001BC07F256C787AA5004051A9037F0A1650C068133305CC9422C07F256C787AA50040A2A11379631F4EC068133305CC9422C07F256C787AA50040A2A11379631F4EC0D0EEFB6B85611CC07F256C787AA50040A2A11379631F4EC0B080FF248F611AC07F256C787AA5004032FB207287324EC0B080FF248F611AC07F256C787AA5004032FB207287324EC0B080FF248F6119C07F256C787AA5004032FA53A5BA354EC0B080FF248F6119C07F256C787AA5004032FA53A5BA354EC050B9B5D2EB4715C07F256C787AA5004032FB207287324EC050B9B5D2EB4715C07F256C787AA5004032FB207287324EC030EA6191DF3D13C07F256C787AA50040A20F302A8DA24EC030EA6191DF3D13C07F256C787AA5004022E08D90F3284FC030EA6191DF3D13C07F256C787AA500409AB0EBF659AF4FC030EA6191DF3D13C07F256C787AA5004051A9037F0A1650C030EA6191DF3D13C07F256C787AA5004051A9037F0A1650C070BA1529D93D1AC07F256C787AA500405A6D1BDCACEE4EC070BA1529D93D1AC07F256C787AA500405A6D1BDCACEE4EC030B03E8568001BC07F256C787AA5004051A9037F0A1650C030B03E8568001BC07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048lP	IFC_COORDSYS_0	01030000A034BF0D0001000000140000000010C12DEE49CFBF500A65D97D9422C07F256C787AA500400010C12DEE49CFBFF8554C4F5CCA21C07F256C787AA500400010C12DEE49CFBFF04B3A66D0231CC07F256C787AA500400010C12DEE49CFBF0014A9FB295C1AC07F256C787AA50040008ACA1DCE76DCBF0014A9FB295C1AC07F256C787AA50040008ACA1DCE76DCBF008AC19F9A9915C07F256C787AA50040001497A2CF95D9BF008AC19F9A9915C07F256C787AA50040001497A2CF95D9BF409498430BD714C07F256C787AA500400088505BB6FDCFBF409498430BD714C07F256C787AA500400088505BB6FDCFBF301739B28C5C13C07F256C787AA5004000864FEC40D6F3BF301739B28C5C13C07F256C787AA50040C0CA04DC865102C0301739B28C5C13C07F256C787AA5004040D2E141EDB70AC0301739B28C5C13C07F256C787AA500408078F527AB7011C0301739B28C5C13C07F256C787AA500408078F527AB7011C05051138B2A801AC07F256C787AA5004000C9B3771AC1FDBF5051138B2A801AC07F256C787AA5004000C9B3771AC1FDBF10473CE7B9421BC07F256C787AA500408078F527AB7011C010473CE7B9421BC07F256C787AA500408078F527AB7011C0500A65D97D9422C07F256C787AA500400010C12DEE49CFBF500A65D97D9422C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048li	IFC_COORDSYS_0	01030000A034BF0D000100000012000000755CA765852252C0A07850A9EECA21C07F256C787AA50040755CA765852252C0809C9623A89C22C07F256C787AA50040896A378D2C1C51C0809C9623A89C22C07F256C787AA50040896A378D2C1C51C0A0523EB9D11A1BC07F256C787AA5004065DE8E3123BC51C0A0523EB9D11A1BC07F256C787AA5004065DE8E3123BC51C0E05C155D42581AC07F256C787AA50040896A378D2C1C51C0E05C155D42581AC07F256C787AA50040896A378D2C1C51C080F870FE635813C07F256C787AA50040F110F9E7D55B51C080F870FE635813C07F256C787AA500402DF9271B099F51C080F870FE635813C07F256C787AA500406DE1564E3CE251C080F870FE635813C07F256C787AA50040A9C0CB5D8B2252C080F870FE635813C07F256C787AA50040A9C0CB5D8B2252C0A09C5720AAE214C07F256C787AA50040C5B2259ABE1552C0A09C5720AAE214C07F256C787AA50040C5B2259ABE1552C0509823933A7C1AC07F256C787AA50040755CA765852252C0509823933A7C1AC07F256C787AA50040755CA765852252C0E06D57D8C8671CC07F256C787AA50040755CA765852252C0A07850A9EECA21C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048iY	IFC_COORDSYS_0	01030000A034BF0D000100000013000000306B908F9B1129C0E0ACFF4F40C821C07F256C787AA50040306B908F9B1129C0A833435BDB9422C07F256C787AA50040F05DA33F68DE20C0A833435BDB9422C07F256C787AA50040F05DA33F68DE20C0806036B7B6291BC07F256C787AA50040905F68FD89DE25C0806036B7B6291BC07F256C787AA50040905F68FD89DE25C0C06A0D5B27671AC07F256C787AA50040F05DA33F68DE20C0C06A0D5B27671AC07F256C787AA50040F05DA33F68DE20C0A086E9DC826713C07F256C787AA500406064167ADCE822C0A086E9DC826713C07F256C787AA5004050773460860225C0A086E9DC826713C07F256C787AA5004030E804AD0F1C27C0A086E9DC826713C07F256C787AA50040A06942DA081229C0A086E9DC826713C07F256C787AA50040A06942DA081229C080FBB8E9939514C07F256C787AA50040309A05A659AB28C080FBB8E9939514C07F256C787AA50040309A05A659AB28C0E05F838CEBCD19C07F256C787AA50040406DC0E3AC1129C0E05F838CEBCD19C07F256C787AA50040406DC0E3AC1129C040325D3A1A2A1AC07F256C787AA50040406DC0E3AC1129C040325D3A1A2A1CC07F256C787AA50040306B908F9B1129C0E0ACFF4F40C821C07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6M6	IFC_COORDSYS_0	01030000A034BF0D000100000009000000F80BE087304A36C0287CABA07E112DC07F256C787AA50040F80BE087304A36C0608DBFFA29042CC07F256C787AA5004090B32F605C8B39C0608DBFFA29042CC07F256C787AA5004090B32F605C8B39C0286C9D313ADD32C07F256C787AA50040A060C016C72336C0286C9D313ADD32C07F256C787AA50040A060C016C72336C070BE8E41EFBD32C07F256C787AA50040D8AA5BCB020836C070BE8E41EFBD32C07F256C787AA50040D8AA5BCB020836C0287CABA07E112DC07F256C787AA50040F80BE087304A36C0287CABA07E112DC07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6M5	IFC_COORDSYS_0	01030000A034BF0D000100000009000000F8FEEF7592E33CC0608DBFFA29042CC07F256C787AA50040F8FEEF7592E33CC0C077254E51012DC07F256C787AA50040D8790424DA243DC0C077254E51012DC07F256C787AA50040D8790424DA243DC08018086F18BE32C07F256C787AA50040B82C9C45E4093DC08018086F18BE32C07F256C787AA50040B82C9C45E4093DC0286C9D313ADD32C07F256C787AA500406057A09D66A239C0286C9D313ADD32C07F256C787AA500406057A09D66A239C0608DBFFA29042CC07F256C787AA50040F8FEEF7592E33CC0608DBFFA29042CC07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6MB	IFC_COORDSYS_0	01030000A034BF0D000100000009000000607246EE96B035C0608DBFFA29042CC07F256C787AA50040607246EE96B035C0287CABA07E112DC07F256C787AA500400007EB8DF8F035C0287CABA07E112DC07F256C787AA500400007EB8DF8F035C070BE8E41EFBD32C07F256C787AA50040D093F349FAD635C070BE8E41EFBD32C07F256C787AA50040D093F349FAD635C02CA074D5AADA32C07F256C787AA500404011C231696E32C02CA074D5AADA32C07F256C787AA500404011C231696E32C0608DBFFA29042CC07F256C787AA50040607246EE96B035C0608DBFFA29042CC07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6MK	IFC_COORDSYS_0	01030000A034BF0D0001000000090000007827873AC9F145C0C8AB17E570162DC07F256C787AA500407827873AC9F145C0C8AB17E570162CC07F256C787AA500401A8293AAA79247C0C8AB17E570162CC07F256C787AA500401A8293AAA79247C024D2B1DF81DE32C07F256C787AA500404CF0F1BB8BDE45C024D2B1DF81DE32C07F256C787AA500404CF0F1BB8BDE45C0DC2BE7C96ABE32C07F256C787AA5004008EA7C6325D145C0DC2BE7C96ABE32C07F256C787AA5004008EA7C6325D145C0C8AB17E570162DC07F256C787AA500407827873AC9F145C0C8AB17E570162DC07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6Nk	IFC_COORDSYS_0	01030000A034BF0D000100000009000000AAF41A8B648B49C088722263BC162DC07F256C787AA50040AAF41A8B648B49C0C8AB17E570162CC07F256C787AA50040BA1B2D44412C4BC0C8AB17E570162CC07F256C787AA50040BA1B2D44412C4BC024D2B1DF81DE32C07F256C787AA50040CAA95055257849C024D2B1DF81DE32C07F256C787AA50040CAA95055257849C08CB556F793BE32C07F256C787AA500403AB710B4C06A49C08CB556F793BE32C07F256C787AA500403AB710B4C06A49C088722263BC162DC07F256C787AA50040AAF41A8B648B49C088722263BC162DC07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6MJ	IFC_COORDSYS_0	01030000A034BF0D000100000009000000E2274EBE973E49C0C8AB17E570162CC07F256C787AA50040E2274EBE973E49C088722263BC162DC07F256C787AA50040526558953B5F49C088722263BC162DC07F256C787AA50040526558953B5F49C08CB556F793BE32C07F256C787AA500406243EAEEBE5149C08CB556F793BE32C07F256C787AA500406243EAEEBE5149C024D2B1DF81DE32C07F256C787AA500400AD44BC92C9E47C024D2B1DF81DE32C07F256C787AA500400AD44BC92C9E47C0C8AB17E570162CC07F256C787AA50040E2274EBE973E49C0C8AB17E570162CC07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6Mg	IFC_COORDSYS_0	01030000A034BF0D00010000000B000000AC7094FEADC545C0E891133C9D4922C07F256C787AA500403C338A270AA545C0E891133C9D4922C07F256C787AA500403C338A270AA545C058FCC28A664523C07F256C787AA5004068B8DD2D930444C058FCC28A664523C07F256C787AA5004068B8DD2D930444C030FB22BC115113C07F256C787AA50040C06F2EBC671D45C030FB22BC115113C07F256C787AA50040C06F2EBC671D45C040CB7F4BD44613C07F256C787AA500405C352C5E4DB845C040CB7F4BD44613C07F256C787AA500405C352C5E4DB845C0E0FAC8F777C613C07F256C787AA50040AC7094FEADC545C0E0FAC8F777C613C07F256C787AA50040AC7094FEADC545C0E891133C9D4922C07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6Ma	IFC_COORDSYS_0	01030000A034BF0D0001000000090000002CB73565142C42C028CB08BE514922C07F256C787AA50040BC792B8E700B42C028CB08BE514922C07F256C787AA50040BC792B8E700B42C058FCC28A664523C07F256C787AA50040A835D992CD6A40C058FCC28A664523C07F256C787AA50040A835D992CD6A40C030FB22BC115113C07F256C787AA5004038D72A7BB11E42C030FB22BC115113C07F256C787AA5004038D72A7BB11E42C040DB96D3CFC513C07F256C787AA500402CB73565142C42C040DB96D3CFC513C07F256C787AA500402CB73565142C42C028CB08BE514922C07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6Mf	IFC_COORDSYS_0	01030000A034BF0D0001000000090000008846F85A3D5842C058FCC28A664523C07F256C787AA500408846F85A3D5842C028CB08BE514922C07F256C787AA500401809EE83993742C028CB08BE514922C07F256C787AA500401809EE83993742C040DB96D3CFC513C07F256C787AA500409C3D91E1174542C040DB96D3CFC513C07F256C787AA500409C3D91E1174542C020937474305613C07F256C787AA500407C66250F0EF943C020937474305613C07F256C787AA500407C66250F0EF943C058FCC28A664523C07F256C787AA500408846F85A3D5842C058FCC28A664523C07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6MZ	IFC_COORDSYS_0	01030000A034BF0D00010000000C000000483F9DF14A7D3DC058FCC28A664523C07F256C787AA50040483F9DF14A7D3DC0D0B72963FF4822C07F256C787AA5004068C48843033C3DC0D0B72963FF4822C07F256C787AA5004068C48843033C3DC000C064AF27C513C07F256C787AA5004040086590FC563DC000C064AF27C513C07F256C787AA5004040086590FC563DC020937474305613C07F256C787AA5004000714B1FBF8C3FC020937474305613C07F256C787AA50040B03C71D735A13FC020937474305613C07F256C787AA50040B03C71D735A13FC030FB22BC115113C07F256C787AA50040BCE32074485F40C030FB22BC115113C07F256C787AA50040BCE32074485F40C058FCC28A664523C07F256C787AA50040483F9DF14A7D3DC058FCC28A664523C07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6LM	IFC_COORDSYS_0	01030000A034BF0D0001000000090000003ACDEA44728B49C058FCC28A664523C07F256C787AA500403ACDEA44728B49C048A5F296EF4922C07F256C787AA50040CA8FE06DCE6A49C048A5F296EF4922C07F256C787AA50040CA8FE06DCE6A49C0301D87AD1CC713C07F256C787AA500404255F15D4D7849C0301D87AD1CC713C07F256C787AA500404255F15D4D7849C0706B396A593213C07F256C787AA50040F2C9499EA5974AC0706B396A593213C07F256C787AA50040F2C9499EA5974AC058FCC28A664523C07F256C787AA500403ACDEA44728B49C058FCC28A664523C07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6LL	IFC_COORDSYS_0	01030000A034BF0D000100000009000000E23D284F495F49C048A5F296EF4922C07F256C787AA500406A001E78A53E49C048A5F296EF4922C07F256C787AA500406A001E78A53E49C058FCC28A664523C07F256C787AA5004022D1679D883248C058FCC28A664523C07F256C787AA5004022D1679D883248C030FB22BC115113C07F256C787AA50040DAEE8AF7E65149C030FB22BC115113C07F256C787AA50040DAEE8AF7E65149C0301D87AD1CC713C07F256C787AA50040E23D284F495F49C0301D87AD1CC713C07F256C787AA50040E23D284F495F49C048A5F296EF4922C07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6Mt	IFC_COORDSYS_0	01030000A034BF0D0001000000090000004887F064C2F135C0D057762BA64822C07F256C787AA50040680CDCB67AB035C0D057762BA64822C07F256C787AA50040680CDCB67AB035C058FCC28A664523C07F256C787AA5004040158D6D449833C058FCC28A664523C07F256C787AA5004040158D6D449833C030FB22BC115113C07F256C787AA5004018B0DF90FCD635C030FB22BC115113C07F256C787AA5004018B0DF90FCD635C080432FD689C413C07F256C787AA500404887F064C2F135C080432FD689C413C07F256C787AA500404887F064C2F135C0D057762BA64822C07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6Mu	IFC_COORDSYS_0	01030000A034BF0D00010000000900000000A67550144A36C058FCC28A664523C07F256C787AA5004000A67550144A36C0D057762BA64822C07F256C787AA50040202B61A2CC0836C0D057762BA64822C07F256C787AA50040202B61A2CC0836C080432FD689C413C07F256C787AA50040E87CAC5DC92336C080432FD689C413C07F256C787AA50040E87CAC5DC92336C020937474305613C07F256C787AA5004090B785857D6238C020937474305613C07F256C787AA5004090B785857D6238C058FCC28A664523C07F256C787AA5004000A67550144A36C058FCC28A664523C07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6M_	IFC_COORDSYS_0	01030000A034BF0D00010000000900000090201806F9243DC0D0B72963FF4822C07F256C787AA50040B0A50358B1E33CC0D0B72963FF4822C07F256C787AA50040B0A50358B1E33CC058FCC28A664523C07F256C787AA50040B813154873CB3AC058FCC28A664523C07F256C787AA50040B813154873CB3AC020937474305613C07F256C787AA50040703B98C32F0A3DC020937474305613C07F256C787AA50040703B98C32F0A3DC000C064AF27C513C07F256C787AA5004090201806F9243DC000C064AF27C513C07F256C787AA5004090201806F9243DC0D0B72963FF4822C07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6Ml	IFC_COORDSYS_0	01030000A034BF0D000100000009000000080057F4D6F145C058FCC28A664523C07F256C787AA50040080057F4D6F145C0E891133C9D4922C07F256C787AA500401C8293AAA7D245C0E891133C9D4922C07F256C787AA500401C8293AAA7D245C0E0FAC8F777C613C07F256C787AA50040C09B92C4B3DE45C0E0FAC8F777C613C07F256C787AA50040C09B92C4B3DE45C030FB22BC115113C07F256C787AA50040102320BC0DFE46C030FB22BC115113C07F256C787AA50040102320BC0DFE46C058FCC28A664523C07F256C787AA50040080057F4D6F145C058FCC28A664523C07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6LS	IFC_COORDSYS_0	01030000A034BF0D00010000000A00000022AC2B6103F74CC098A97F17474A22C07F256C787AA500400AE5F51F0BC54CC098A97F17474A22C07F256C787AA500400AE5F51F0BC54CC058FCC28A664523C07F256C787AA500404A0E102420CC4BC058FCC28A664523C07F256C787AA500404A0E102420CC4BC0706B396A593213C07F256C787AA50040BA1CEC9080EB4CC0706B396A593213C07F256C787AA50040BA1CEC9080EB4CC0704FD1F4BDC713C07F256C787AA5004022AC2B6103F74CC0704FD1F4BDC713C07F256C787AA5004022AC2B6103F74CC00015E8FE66611AC07F256C787AA5004022AC2B6103F74CC098A97F17474A22C07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6Mn	IFC_COORDSYS_0	01030000A034BF0D00010000000A00000090950CE5957A2EC058FCC28A664523C07F256C787AA5004090950CE5957A2EC0B83ED187554822C07F256C787AA50040E00946FE81B02DC0B83ED187554822C07F256C787AA50040E00946FE81B02DC0E0D47EF7372A1CC07F256C787AA50040E00946FE81B02DC070DA9843DEC313C07F256C787AA500405042D4552CE12DC070DA9843DEC313C07F256C787AA500405042D4552CE12DC020937474305613C07F256C787AA50040F0FBD222C82E31C020937474305613C07F256C787AA50040F0FBD222C82E31C058FCC28A664523C07F256C787AA5004090950CE5957A2EC058FCC28A664523C07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6LR	IFC_COORDSYS_0	01030000A034BF0D0001000000050000006ABC57059BC04BC0C06B396A593213C07F256C787AA500406ABC57059BC04BC030FCC28A664523C07F256C787AA50040D21B02BD2AA34AC030FCC28A664523C07F256C787AA50040D21B02BD2AA34AC0C06B396A593213C07F256C787AA500406ABC57059BC04BC0C06B396A593213C07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6Mo	IFC_COORDSYS_0	01030000A034BF0D000100000008000000C89F4360D24531C058FCC28A664523C07F256C787AA50040C89F4360D24531C020937474305613C07F256C787AA50040D0CE647C4E4F32C020937474305613C07F256C787AA50040A83BEC3AC56332C020937474305613C07F256C787AA50040A83BEC3AC56332C030FB22BC115113C07F256C787AA5004068711C303A8133C030FB22BC115113C07F256C787AA5004068711C303A8133C058FCC28A664523C07F256C787AA50040C89F4360D24531C058FCC28A664523C07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6LG	IFC_COORDSYS_0	01030000A034BF0D0001000000050000003A7FAF7E032748C090FA22BC115113C07F256C787AA500403A7FAF7E032748C0A8FCC28A664523C07F256C787AA50040F874D8DA920947C0A8FCC28A664523C07F256C787AA50040F874D8DA920947C090FA22BC115113C07F256C787AA500403A7FAF7E032748C090FA22BC115113C07F256C787AA50040
second_floor	1BUg4a4jr0B9Q5NnDgB6Mz	IFC_COORDSYS_0	01030000A034BF0D0001000000050000000071A40A69B43AC030957474305613C07F256C787AA500400071A40A69B43AC088FDC28A664523C07F256C787AA50040805CF6C2877938C088FDC28A664523C07F256C787AA50040805CF6C2877938C030957474305613C07F256C787AA500400071A40A69B43AC030957474305613C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048il	IFC_COORDSYS_0	01030000A034BF0D000100000007000000F05DA33F68DE20C0A0E046B84ECE02C07F256C787AA50040F05DA33F68DE20C00060CB53C288CDBF7F256C787AA50040A06942DA081229C00060CB53C288CDBF7F256C787AA50040A06942DA081229C0803AACF1480202C07F256C787AA50040E088EE88E2D128C0803AACF1480202C07F256C787AA50040E088EE88E2D128C0A0E046B84ECE02C07F256C787AA50040F05DA33F68DE20C0A0E046B84ECE02C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048ie	IFC_COORDSYS_0	01030000A034BF0D00010000000500000000E4FFFFFFFFCFBF00CCE64694CD02C07F256C787AA5004000E4FFFFFFFFCFBF002C00000000D0BF7F256C787AA500406079F527AB7011C0002C00000000D0BF7F256C787AA500406079F527AB7011C000CCE64694CD02C07F256C787AA5004000E4FFFFFFFFCFBF00CCE64694CD02C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048l7	IFC_COORDSYS_0	01030000A034BF0D00010000000A0000004080F1E91F1129C0C822E09DF14737C07F256C787AA500404080F1E91F9128C0C822E09DF14737C07F256C787AA500404080F1E91F9128C0D455E776FE4C37C07F256C787AA50040F0A1A28ED95D21C0D455E776FE4C37C07F256C787AA50040F0A1A28ED95D21C0C099A290244937C07F256C787AA50040F05DA33F68DE20C0C099A290244937C07F256C787AA50040F05DA33F68DE20C0FC6CBB21A11A37C07F256C787AA50040F05DA33F68DE20C0846DACB4C13435C07F256C787AA500404080F1E91F1129C0846DACB4C13435C07F256C787AA500404080F1E91F1129C0C822E09DF14737C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048l0	IFC_COORDSYS_0	01030000A034BF0D0001000000070000008080684564C428C068655E3C302033C07F256C787AA500408080684564C428C0A019216DE05933C07F256C787AA500404080F1E91F1129C0A019216DE05933C07F256C787AA500404080F1E91F1129C00859FE6CE0F934C07F256C787AA50040F05DA33F68DE20C00859FE6CE0F934C07F256C787AA50040F05DA33F68DE20C068655E3C302033C07F256C787AA500408080684564C428C068655E3C302033C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048lg	IFC_COORDSYS_0	01030000A034BF0D00010000000A00000025690C80DE1852C07082A9B0681C33C07F256C787AA5004025690C80DE1852C0D47D30D7415233C07F256C787AA50040959FEC43F21652C0D47D30D7415233C07F256C787AA50040959FEC43F21652C0B899BA20445234C07F256C787AA5004039F7E498741252C0B899BA20445234C07F256C787AA5004039F7E498741252C000AD1B735EE534C07F256C787AA5004039548F320E2C51C000AD1B735EE534C07F256C787AA5004039548F320E1C51C000AD1B735EE534C07F256C787AA5004039548F320E1C51C07082A9B0681C33C07F256C787AA5004025690C80DE1852C07082A9B0681C33C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048lE	IFC_COORDSYS_0	01030000A034BF0D00010000000F000000F239625928584DC010F390590F9730C07F256C787AA50040AA58E7447A304DC010F390590F9730C07F256C787AA50040AA58E7447A304DC0A09878F413172DC07F256C787AA50040AA58E7447A304DC0686545C1E0E32BC07F256C787AA50040AA58E7447A304DC0E8665D4DB8C728C07F256C787AA50040729D11BACC3A4DC0E8665D4DB8C728C07F256C787AA5004012BF4DABE0564DC0E8665D4DB8C728C07F256C787AA50040FA2C3D8DE0FF4DC0E8665D4DB8C728C07F256C787AA50040FA2C3D8DE0FF4DC000245E4E0E412CC07F256C787AA50040FA2C3D8DE0FF4DC0108DFC3F5C4A2CC07F256C787AA5004072B89C2B97FE4DC0108DFC3F5C4A2CC07F256C787AA5004072B89C2B97FE4DC0B8169694658F2CC07F256C787AA5004072B89C2B97FE4DC008D6ECA4199730C07F256C787AA50040020C8D8C5BDB4DC008D6ECA4199730C07F256C787AA50040F239625928584DC010F390590F9730C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048iX	IFC_COORDSYS_0	01030000A034BF0D00010000000500000080C1A53CD2D122C0A0D4C58B46B00AC07F256C787AA5004080C1A53CD2D122C0F0F826E7590B13C07F256C787AA50040405FA33F68DE20C0F0F826E7590B13C07F256C787AA50040405FA33F68DE20C0A0D4C58B46B00AC07F256C787AA5004080C1A53CD2D122C0A0D4C58B46B00AC07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048lL	IFC_COORDSYS_0	01030000A034BF0D000100000005000000C060A43716140BC0208876BC630013C07F256C787AA50040C060A43716140BC000616977349A0AC07F256C787AA50040E078F527AB7011C000616977349A0AC07F256C787AA50040E078F527AB7011C0208876BC630013C07F256C787AA50040C060A43716140BC0208876BC630013C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048lB	IFC_COORDSYS_0	01030000A034BF0D000100000005000000B2E6D39ACA9C4EC000C5D9A6D78F0AC07F256C787AA50040B2E6D39ACA9C4EC040599F9BB6E112C07F256C787AA500409AA11379631F4EC040599F9BB6E112C07F256C787AA500409AA11379631F4EC000C5D9A6D78F0AC07F256C787AA50040B2E6D39ACA9C4EC000C5D9A6D78F0AC07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048ia	IFC_COORDSYS_0	01030000A034BF0D000100000005000000500787B7E6FF22C0A0D4C58B46B00AC07F256C787AA5004030D2C3227CEB24C0A0D4C58B46B00AC07F256C787AA5004030D2C3227CEB24C0F0F826E7590B13C07F256C787AA50040500787B7E6FF22C0F0F826E7590B13C07F256C787AA50040500787B7E6FF22C0A0D4C58B46B00AC07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048lJ	IFC_COORDSYS_0	01030000A034BF0D000100000005000000C03A42E65DF501C0208876BC630013C07F256C787AA5004080A6D4D7928EF4BF208876BC630013C07F256C787AA5004080A6D4D7928EF4BF00616977349A0AC07F256C787AA50040C03A42E65DF501C000616977349A0AC07F256C787AA50040C03A42E65DF501C0208876BC630013C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048lM	IFC_COORDSYS_0	01030000A034BF0D00010000000500000040421F4CC45B0AC0208876BC630013C07F256C787AA50040C05AC7D1AFAD02C0208876BC630013C07F256C787AA50040C05AC7D1AFAD02C000616977349A0AC07F256C787AA5004040421F4CC45B0AC000616977349A0AC07F256C787AA5004040421F4CC45B0AC0208876BC630013C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048ix	IFC_COORDSYS_0	01030000A034BF0D000100000005000000201AA59D901925C0A0D4C58B46B00AC07F256C787AA500402043946F050527C0A0D4C58B46B00AC07F256C787AA500402043946F050527C0F0F826E7590B13C07F256C787AA50040201AA59D901925C0F0F826E7590B13C07F256C787AA50040201AA59D901925C0A0D4C58B46B00AC07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048lS	IFC_COORDSYS_0	01030000A034BF0D000100000005000000006ACA00EF1DF3BF208876BC630013C07F256C787AA500400070505BB6FDCFBF208876BC630013C07F256C787AA500400070505BB6FDCFBF00616977349A0AC07F256C787AA50040006ACA00EF1DF3BF00616977349A0AC07F256C787AA50040006ACA00EF1DF3BF208876BC630013C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048lb	IFC_COORDSYS_0	01030000A034BF0D000100000005000000B1E479D3279C51C0D06BAE083BFC12C07F256C787AA500407125A72FB75E51C0D06BAE083BFC12C07F256C787AA500407125A72FB75E51C0A01D6F3B8DC40AC07F256C787AA50040B1E479D3279C51C0A01D6F3B8DC40AC07F256C787AA50040B1E479D3279C51C0D06BAE083BFC12C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048lc	IFC_COORDSYS_0	01030000A034BF0D000100000005000000EDCCA8065BDF51C0D06BAE083BFC12C07F256C787AA50040B10DD662EAA151C0D06BAE083BFC12C07F256C787AA50040B10DD662EAA151C0A01D6F3B8DC40AC07F256C787AA50040EDCCA8065BDF51C0A01D6F3B8DC40AC07F256C787AA50040EDCCA8065BDF51C0D06BAE083BFC12C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048ln	IFC_COORDSYS_0	01030000A034BF0D000100000005000000A2878F6797A94FC040599F9BB6E112C07F256C787AA500401A09EA1FB62E4FC040599F9BB6E112C07F256C787AA500401A09EA1FB62E4FC000C5D9A6D78F0AC07F256C787AA50040A2878F6797A94FC000C5D9A6D78F0AC07F256C787AA50040A2878F6797A94FC040599F9BB6E112C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048lq	IFC_COORDSYS_0	01030000A034BF0D00010000000500000022B7310131234FC040599F9BB6E112C07F256C787AA50040AA388CB94FA84EC040599F9BB6E112C07F256C787AA50040AA388CB94FA84EC000C5D9A6D78F0AC07F256C787AA5004022B7310131234FC000C5D9A6D78F0AC07F256C787AA5004022B7310131234FC040599F9BB6E112C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048lZ	IFC_COORDSYS_0	01030000A034BF0D000100000005000000A9C0CB5D8B2252C06095D54154C50AC07F256C787AA50040A9C0CB5D8B2252C02069AE083BFC12C07F256C787AA50040E5F504961DE551C02069AE083BFC12C07F256C787AA50040E5F504961DE551C0401A6F3B8DC40AC07F256C787AA50040A9C0CB5D8B2252C06095D54154C50AC07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048i_	IFC_COORDSYS_0	01030000A034BF0D000100000007000000A06942DA081229C050F726E7590B13C07F256C787AA50040008C75EA193327C050F726E7590B13C07F256C787AA50040008C75EA193327C0E0D7C58B46B00AC07F256C787AA50040E088EE88E2D128C0E0D7C58B46B00AC07F256C787AA50040E088EE88E2D128C0A067AFDDFECE0AC07F256C787AA50040A06942DA081229C0A067AFDDFECE0AC07F256C787AA50040A06942DA081229C050F726E7590B13C07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048lu	IFC_COORDSYS_0	01030000A034BF0D00010000000500000069FC4AA0F45851C0A01D6F3B8DC40AC07F256C787AA5004069FC4AA0F45851C0D06BAE083BFC12C07F256C787AA50040556A378D2C1C51C0D06BAE083BFC12C07F256C787AA50040556A378D2C1C51C0A01D6F3B8DC40AC07F256C787AA5004069FC4AA0F45851C0A01D6F3B8DC40AC07F256C787AA50040
second_floor	1mWTVVwiXDHQKYjSZ048lo	IFC_COORDSYS_0	01030000A034BF0D00010000000500000072D947861CB54FC040599F9BB6E112C07F256C787AA5004072D947861CB54FC000C5D9A6D78F0AC07F256C787AA5004061A9037F0A1650C000C5D9A6D78F0AC07F256C787AA5004061A9037F0A1650C040599F9BB6E112C07F256C787AA5004072D947861CB54FC040599F9BB6E112C07F256C787AA50040
\.


--
-- Data for Name: spatial_ref_sys; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.spatial_ref_sys (srid, auth_name, auth_srid, srtext, proj4text) FROM stdin;
900914	\N	\N	PROJCS["IFC_COORDSYS_0",GEOGCS["GCS_WGS_1984",DATUM["WGS_1984",SPHEROID["World_Geodetic_System_of_1984_GEM_10C",6378137,298.257223563]],PRIMEM["Greenwich",0],UNIT["Degree",0.017453292519943295],AUTHORITY["EPSG","4326"]],PROJECTION["Azimuthal_Equidistant"],PARAMETER["latitude_of_center",42.35866165138889],PARAMETER["longitude_of_center",-71.05673980694444],PARAMETER["false_easting",0],PARAMETER["false_northing",0],UNIT["Meter",1]]	+proj=aeqd +lat_0=42.35866165138889 +lon_0=-71.05673980694444 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs 
900915	USER	900915	PROJCS["IFC_COORDSYS_0",GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["World Geodetic System of 1984, GEM 10C",6378137,298.257223563,AUTHORITY["EPSG","7030"]],AUTHORITY["EPSG","6326"]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433],AUTHORITY["EPSG","4326"]],PROJECTION["Azimuthal_Equidistant"],PARAMETER["latitude_of_center",42.35866165138889],PARAMETER["longitude_of_center",-71.05673980694444],PARAMETER["false_easting",0],PARAMETER["false_northing",0],UNIT["METER",1]]	+proj=aeqd +lat_0=42.35866165138889 +lon_0=-71.05673980694444 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs 
900916	USER	900916	PROJCS["IFC_COORDSYS_0",GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["World Geodetic System of 1984, GEM 10C",6378137,298.257223563,AUTHORITY["EPSG","7030"]],AUTHORITY["EPSG","6326"]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433],AUTHORITY["EPSG","4326"]],PROJECTION["Azimuthal_Equidistant"],PARAMETER["latitude_of_center",41.10448455805556],PARAMETER["longitude_of_center",29.01986885055555],PARAMETER["false_easting",0],PARAMETER["false_northing",0],UNIT["METER",1]]	+proj=aeqd +lat_0=41.10448455805556 +lon_0=29.01986885055555 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs 
\.


--
-- Name: edges_vertices_pgr_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.edges_vertices_pgr_id_seq', 614, true);


--
-- Name: first_floor_edges_noded_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.first_floor_edges_noded_id_seq', 1772, true);


--
-- Name: first_floor_edges_vertices_pgr_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.first_floor_edges_vertices_pgr_id_seq', 614, true);


--
-- Name: second_floor_edges_vertices_pgr_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.second_floor_edges_vertices_pgr_id_seq', 303, true);


--
-- Name: edges edges_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.edges
    ADD CONSTRAINT edges_pkey PRIMARY KEY (_id);


--
-- Name: edges_vertices_pgr edges_vertices_pgr_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.edges_vertices_pgr
    ADD CONSTRAINT edges_vertices_pgr_pkey PRIMARY KEY (id);


--
-- Name: first_floor_edges_noded first_floor_edges_noded_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.first_floor_edges_noded
    ADD CONSTRAINT first_floor_edges_noded_pkey PRIMARY KEY (id);


--
-- Name: first_floor_edges first_floor_edges_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.first_floor_edges
    ADD CONSTRAINT first_floor_edges_pkey PRIMARY KEY (_id);


--
-- Name: first_floor_edges_vertices_pgr first_floor_edges_vertices_pgr_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.first_floor_edges_vertices_pgr
    ADD CONSTRAINT first_floor_edges_vertices_pgr_pkey PRIMARY KEY (id);


--
-- Name: rooms rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rooms
    ADD CONSTRAINT rooms_pkey PRIMARY KEY (_area_id);


--
-- Name: second_floor_edges second_floor_edges_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.second_floor_edges
    ADD CONSTRAINT second_floor_edges_pkey PRIMARY KEY (_id);


--
-- Name: second_floor_edges_vertices_pgr second_floor_edges_vertices_pgr_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.second_floor_edges_vertices_pgr
    ADD CONSTRAINT second_floor_edges_vertices_pgr_pkey PRIMARY KEY (id);


--
-- Name: second_floor_rooms second_floor_rooms_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.second_floor_rooms
    ADD CONSTRAINT second_floor_rooms_pkey PRIMARY KEY (_area_id);


--
-- Name: edges_geom_1570564425726; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX edges_geom_1570564425726 ON public.edges USING gist (geom);


--
-- Name: edges_source_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX edges_source_idx ON public.edges USING btree (source);


--
-- Name: edges_target_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX edges_target_idx ON public.edges USING btree (target);


--
-- Name: edges_vertices_pgr_the_geom_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX edges_vertices_pgr_the_geom_idx ON public.edges_vertices_pgr USING gist (the_geom);


--
-- Name: first_floor_edges_geom_1569772429802; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX first_floor_edges_geom_1569772429802 ON public.first_floor_edges USING gist (geom);


--
-- Name: first_floor_edges_noded_geom_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX first_floor_edges_noded_geom_idx ON public.first_floor_edges_noded USING gist (geom);


--
-- Name: first_floor_edges_source_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX first_floor_edges_source_idx ON public.first_floor_edges USING btree (source);


--
-- Name: first_floor_edges_target_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX first_floor_edges_target_idx ON public.first_floor_edges USING btree (target);


--
-- Name: first_floor_edges_vertices_pgr_the_geom_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX first_floor_edges_vertices_pgr_the_geom_idx ON public.first_floor_edges_vertices_pgr USING gist (the_geom);


--
-- Name: first_floor_rooms_geom_1569784267148; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX first_floor_rooms_geom_1569784267148 ON public.first_floor_rooms USING gist (geom);


--
-- Name: rooms_geom_1570655199287; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX rooms_geom_1570655199287 ON public.rooms USING gist (geom);


--
-- Name: second_floor_edges_geom_1569751750793; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX second_floor_edges_geom_1569751750793 ON public.second_floor_edges USING gist (geom);


--
-- Name: second_floor_edges_vertices_pgr_the_geom_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX second_floor_edges_vertices_pgr_the_geom_idx ON public.second_floor_edges_vertices_pgr USING gist (the_geom);


--
-- Name: second_floor_rooms_geom_1569784267151; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX second_floor_rooms_geom_1569784267151 ON public.second_floor_rooms USING gist (geom);


--
-- PostgreSQL database dump complete
--

