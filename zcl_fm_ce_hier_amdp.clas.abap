CLASS zcl_fm_ce_hier_amdp DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_amdp_marker_hdb .

    " New TF: cost element hierarchy
    CLASS-METHODS get
        FOR TABLE FUNCTION zi_cehiertf.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_fm_ce_hier_amdp IMPLEMENTATION.
  METHOD get BY DATABASE FUNCTION
     FOR HDB LANGUAGE SQLSCRIPT
     OPTIONS READ-ONLY
     USING setheader setheadert setnode setleaf ska1.

    -----------------------------------------------------------------------
    -- Parameters:
    --  p_setclass : Set class for cost element sets (e.g. 0101 / 0106 etc.)
    --  p_setname  : Root set name (e.g. TOTAL or your ce root)
    --  p_ktopl    : reused here as subclass / chart-of-accounts key for sets
    --               (adjust meaning if needed in your config)
    -----------------------------------------------------------------------

    declare lv_setclass nvarchar(4)  := :p_setclass;    -- ce set class
    declare lv_root     nvarchar(30) := :p_setname;     -- root set name
    /* system language in sap 1-char format (E, d, f, ...); fallback to 'E' */
    declare lv_langu    nvarchar(1)  := COALESCE(session_context('LOCALE_SAP'), 'E');

    -----------------------------------------------------------------------
    -- 1) build full set hierarchy from ROOT downward (bfs)
    -----------------------------------------------------------------------
    lt_curr_lvl =
      SELECT
        n.mandt,
        n.subsetname                                     AS setname,
        1                                                AS lvl,
        h.setname                                        AS parentset,
        h.setname                                        AS rootset,
        n.seqnr                                          AS setsequencenumber,
        to_nvarchar(h.setname) || ' > ' || n.subsetname  AS path
        FROM setheader h
        JOIN setnode   n
          ON  n.mandt     = h.mandt
          AND n.setclass  = h.setclass
          AND n.subclass  = h.subclass
          AND n.setname   = h.setname
       WHERE h.mandt    = :p_clnt
         AND h.setclass = lv_setclass
         AND h.setname  = lv_root
         AND h.subclass = :p_ktopl;

    lt_all_lvls = SELECT * FROM :lt_curr_lvl;

    WHILE 1 = 1 DO

      lt_next_lvl =
        SELECT
          n2.mandt,
          n2.subsetname                             AS setname,
          c.lvl + 1                                 AS lvl,
          c.setname                                 AS parentset,
          c.rootset                                 AS rootset,
          n2.seqnr                                  AS setsequencenumber,
          c.path || ' > ' || n2.subsetname          AS path
          FROM :lt_curr_lvl c
          JOIN setnode n2
            ON  n2.mandt    = c.mandt
            AND n2.setclass = lv_setclass
            AND n2.subclass = :p_ktopl
            AND n2.setname  = c.setname
          LEFT JOIN :lt_all_lvls a
            ON  a.mandt = n2.mandt
            AND a.setname = n2.subsetname
         WHERE a.setname IS null;

      IF ( SELECT COUNT(*) FROM :lt_next_lvl ) = 0 THEN
        break;
      END if;

      lt_all_lvls =
        SELECT * FROM :lt_all_lvls
        UNION ALL
        SELECT * FROM :lt_next_lvl;

      lt_curr_lvl = SELECT * FROM :lt_next_lvl;

    END while;

    -- Include ROOT as level 0
    lt_root_row =
      SELECT
        h.mandt,
        h.setname AS setname,
        0         AS lvl,
        h.setname AS parentset,
        h.setname AS rootset,
        CAST('0' AS nvarchar(10)) AS setsequencenumber,
        to_nvarchar(h.setname) AS path
        FROM setheader h
       WHERE h.mandt    = :p_clnt
         AND h.setclass = lv_setclass
         AND h.setname  = lv_root
         AND h.subclass = :p_ktopl;

    lt_all_lvls =
      SELECT * FROM :lt_all_lvls
      UNION ALL
      SELECT * FROM :lt_root_row;

    -----------------------------------------------------------------------
    -- 2) Sets that carry ranges
    -----------------------------------------------------------------------
    lt_sets_with_ranges =
      SELECT
        l.mandt,
        l.setname,
        MIN(l.valfrom) AS any_from,
        MAX(l.valto)   AS any_to
        FROM setleaf l
       WHERE l.mandt    = :p_clnt
         AND l.setclass = lv_setclass
         AND l.setname  IN ( SELECT setname
                               FROM :lt_all_lvls
                              WHERE mandt = :p_clnt )
       GROUP BY l.mandt, l.setname;

    lt_sets_with_children =
      SELECT DISTINCT
        n.mandt,
        n.setname
        FROM setnode n
       WHERE n.mandt    = :p_clnt
         AND n.setclass = lv_setclass
         AND n.subclass = :p_ktopl;

    lt_true_leaf_sets =
      SELECT
        r.mandt,
        r.setname
        FROM :lt_sets_with_ranges r
        LEFT JOIN :lt_sets_with_children c
          ON  c.mandt = r.mandt
          AND c.setname = r.setname
       WHERE c.setname IS null;

    -----------------------------------------------------------------------
    -- 3) cost element (racct) -> immediate parent (leaf set)
    -----------------------------------------------------------------------
    lt_leaf_sets =
      SELECT
        a.mandt,
        a.setname         AS leaf_set,        -- immediate parent set
        a.lvl             AS leaflevel,
        a.rootset,
        a.setsequencenumber,
        a.path            AS leaf_path
        FROM :lt_all_lvls a
        JOIN :lt_sets_with_ranges r
          ON  r.mandt   = a.mandt
          AND r.setname = a.setname;

    lt_join_for_expand =
      SELECT
        ls.mandt,
        ls.leaf_set,
        ls.leaflevel,
        ls.rootset,
        ls.setsequencenumber,
        ls.leaf_path  AS path,
        l.valfrom,
        l.valto
        FROM :lt_leaf_sets ls
        JOIN setleaf l
          ON  l.mandt    = ls.mandt
          AND l.setclass = lv_setclass
          AND l.subclass = :p_ktopl
          AND l.setname  = ls.leaf_set;


 lt_rows_racct_parent =
(
  /* ------------------------------------------------
     a) SINGLE VALUES: valfrom = valto -> equality join
     ------------------------------------------------ */
  SELECT DISTINCT
    c.mandt                                   AS client,
    :p_ktopl                                  AS ktopl,
    c.saknr                                   AS racct,
    sht_leaf.descript                         AS settext,
    j.leaf_set                                AS parentset,
    j.leaflevel                               AS parentlevel,
    COALESCE(sht.descript, sh.setname)        AS parentsettext,
    j.rootset                                 AS rootset,
    j.setsequencenumber                       AS setsequencenumber,
    j.path                                    AS path
  FROM :lt_join_for_expand j
  JOIN ska1 c
    ON  c.mandt = j.mandt
    AND c.ktopl = :p_ktopl
    AND LPAD(c.saknr, LENGTH(j.valfrom), '0') = j.valfrom
  LEFT JOIN setheader sh
    ON  sh.mandt    = j.mandt
    AND sh.setclass = lv_setclass
    AND sh.subclass = :p_ktopl
    AND sh.setname  = j.leaf_set
  LEFT JOIN setheadert sht
    ON  sht.mandt    = sh.mandt
    AND sht.setclass = sh.setclass
    AND sht.subclass = sh.subclass
    AND sht.setname  = sh.setname
    AND sht.langu    = lv_langu
  LEFT JOIN setheadert sht_leaf
    ON  sht_leaf.mandt    = sh.mandt
    AND sht_leaf.setclass = sh.setclass
    AND sht_leaf.subclass = sh.subclass
    AND sht_leaf.setname  = j.leaf_set
    AND sht_leaf.langu    = lv_langu
  WHERE j.valfrom = j.valto

  UNION ALL

  /* ------------------------------------------------
     b) true RANGES: valfrom <> valto -> BETWEEN join
     ------------------------------------------------ */
  SELECT DISTINCT
    c.mandt                                   AS client,
    :p_ktopl                                  AS ktopl,
    c.saknr                                   AS racct,
    sht_leaf.descript                         AS settext,
    j.leaf_set                                AS parentset,
    j.leaflevel                               AS parentlevel,
    COALESCE(sht.descript, sh.setname)        AS parentsettext,
    j.rootset                                 AS rootset,
    j.setsequencenumber                       AS setsequencenumber,
    j.path                                    AS path
  FROM :lt_join_for_expand j
  JOIN ska1 c
    ON  c.mandt = j.mandt
    AND c.ktopl = :p_ktopl
    AND LPAD(c.saknr, LENGTH(j.valfrom), '0')
        BETWEEN j.valfrom AND j.valto
  LEFT JOIN setheader sh
    ON  sh.mandt    = j.mandt
    AND sh.setclass = lv_setclass
    AND sh.subclass = :p_ktopl
    AND sh.setname  = j.leaf_set
  LEFT JOIN setheadert sht
    ON  sht.mandt    = sh.mandt
    AND sht.setclass = sh.setclass
    AND sht.subclass = sh.subclass
    AND sht.setname  = sh.setname
    AND sht.langu    = lv_langu
  LEFT JOIN setheadert sht_leaf
    ON  sht_leaf.mandt    = sh.mandt
    AND sht_leaf.setclass = sh.setclass
    AND sht_leaf.subclass = sh.subclass
    AND sht_leaf.setname  = j.leaf_set
    AND sht_leaf.langu    = lv_langu
  WHERE j.valfrom <> j.valto
);

    -----------------------------------------------------------------------
    -- 4) SET -> parent SET edges (still carried in the racct column)
    -----------------------------------------------------------------------
    lt_rows_set_to_parent =
      SELECT DISTINCT
        a.mandt                                   AS client,
        :p_ktopl                                  AS ktopl,
        CAST(a.setname AS nvarchar(24))           AS racct,          -- child = set name
        shta.descript                             AS settext,
        a.parentset                               AS parentset,
        p.lvl                                     AS parentlevel,
        COALESCE(shtp.descript, p.setname)        AS parentsettext,
        a.rootset                                 AS rootset,
        a.setsequencenumber                       AS setsequencenumber,
        p.path                                    AS path
        FROM :lt_all_lvls a
        JOIN :lt_all_lvls p
          ON  p.mandt   = a.mandt
          AND p.setname = a.parentset
        LEFT JOIN setheader shp
          ON  shp.mandt    = p.mandt
          AND shp.setclass = lv_setclass
          AND shp.subclass = :p_ktopl
          AND shp.setname  = p.setname
        LEFT JOIN setheadert shtp
          ON  shtp.mandt    = shp.mandt
          AND shtp.setclass = shp.setclass
          AND shtp.subclass = shp.subclass
          AND shtp.setname  = shp.setname
          AND shtp.langu    = lv_langu
        LEFT JOIN setheader sha
          ON  sha.mandt    = a.mandt
          AND sha.setclass = lv_setclass
          AND sha.subclass = :p_ktopl
          AND sha.setname  = a.setname
        LEFT JOIN setheadert shta
          ON  shta.mandt    = sha.mandt
          AND shta.setclass = sha.setclass
          AND shta.subclass = sha.subclass
          AND shta.setname  = sha.setname
          AND shta.langu    = lv_langu
       WHERE a.lvl > 0;  -- exclude root self-edge

    -----------------------------------------------------------------------
    -- 5) RETURN: racct->parent  UNION  set->parent
    -----------------------------------------------------------------------
    RETURN
      SELECT * FROM :lt_rows_racct_parent
      UNION ALL
      SELECT * FROM :lt_rows_set_to_parent;

  ENDMETHOD.
ENDCLASS.