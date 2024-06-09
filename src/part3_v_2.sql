-----------------------------!!!ВНИМАНИЕ!!!-----------------------------
-- В данном файле реализация ВСЕХ заданий через функции, а не через процедуры как в файле part3_v_1.sql
-----------------------------!!!ВНИМАНИЕ!!!-----------------------------

DELETE FROM transferred_points;
DELETE FROM p2p;
DELETE FROM verter;
DELETE FROM xp;
DELETE FROM checks;
ALTER SEQUENCE transferred_points_id_seq RESTART WITH 1;
ALTER SEQUENCE p2p_id_seq RESTART WITH 1;
ALTER SEQUENCE verter_id_seq RESTART WITH 1;
ALTER SEQUENCE xp_id_seq RESTART WITH 1;
ALTER SEQUENCE checks_id_seq RESTART WITH 1;

--------------------- BEFORE TASKS NEED FILL DATA INTO TIMETRACKING TABLE ---------------------

-- -- PLEASE RUN timetracking_fill_data.sql


------------------------ ADDITIONAL VIEW, FUNCTION, TRIGGER ---------------------------------

-- вспомогательная MATERIALIZED VIEW mv_checks, так как в разных tasks присутсвует
-- одинаковый запрос к одним и тем же данным

DROP MATERIALIZED VIEW IF EXISTS mv_checks;
CREATE MATERIALIZED VIEW mv_checks AS
SELECT  ch.id,
        ch.date,
        ch.peer,
        ch.task,
        CASE WHEN v.state = 'Failure' OR p2p.state = 'Failure'
                 THEN 'Failure'
             ELSE 'Success'
            END AS state
FROM checks ch
         JOIN p2p ON p2p.check_id = ch.id AND NOT p2p.state = 'Start'
         LEFT JOIN verter v ON v.check_id = ch.id AND NOT v.state = 'Start';

-- функция обновления VIEW mv_checks
CREATE OR REPLACE FUNCTION fnc_refresh_mv_checks()
    RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_checks;
    RETURN NULL;
END;$$;

-- триггер обновления VIEW mv_checks, если обновятся данные в p2p table
CREATE OR REPLACE TRIGGER tg_refresh_mv_checks AFTER INSERT OR UPDATE OR DELETE
    ON p2p
    FOR EACH STATEMENT EXECUTE PROCEDURE fnc_refresh_mv_checks();

-- триггер обновления VIEW mv_checks, если обновятся данные в verter table
CREATE OR REPLACE TRIGGER tg_refresh_mv_checks AFTER INSERT OR UPDATE OR DELETE
    ON verter
    FOR EACH STATEMENT EXECUTE PROCEDURE fnc_refresh_mv_checks();


------------------------------------ TASKS ---------------------------------------------

-- 1) Написать функцию, возвращающую таблицу TransferredPoints в более человекочитаемом виде
CREATE OR REPLACE FUNCTION fnc_task1()
    RETURNS TABLE ("Peer1" varchar, "Peer2" varchar, "PointsAmount" integer) AS $$
WITH tmp AS (
    SELECT tp.checking_peer, tp.checked_peer, tp.points_amount FROM transferred_points tp
                                                                        JOIN transferred_points t2 ON t2.checking_peer = tp.checked_peer
        AND t2.checked_peer = tp.checking_peer AND tp.id < t2.id
            )
            (SELECT checking_peer, checked_peer, sum(res.points_amount)
            FROM (SELECT f.checking_peer, f.checked_peer, f.points_amount FROM transferred_points f
                UNION
                SELECT t.checked_peer, t.checking_peer, -t.points_amount FROM tmp t) AS res
            GROUP BY 1, 2)
            EXCEPT
SELECT t.checking_peer, t.checked_peer, t.points_amount FROM tmp t
ORDER BY 1;
$$ LANGUAGE sql;

SELECT * FROM fnc_task1();

-- 2) Написать функцию, которая возвращает таблицу вида: ник пользователя, название проверенного задания, кол-во полученного XP
CREATE OR REPLACE FUNCTION fnc_task2()
    RETURNS TABLE ("Peer" varchar, "Task" varchar, "XP" integer) AS $$
SELECT ch.peer, ch.task, xp.xp_amount
FROM mv_checks ch
         JOIN xp ON xp.check_id = ch.id
WHERE ch.state = 'Success'
ORDER BY 1, 3 DESC;
$$ LANGUAGE sql;

SELECT * FROM fnc_task2();

-- 3) Написать функцию, определяющую пиров, которые не выходили из кампуса в течение всего дня
CREATE OR REPLACE FUNCTION fnc_task3(IN pdate date)
    RETURNS TABLE (peer VARCHAR) AS $$
SELECT peer FROM time_tracking
WHERE date = pdate AND state = 1
GROUP BY peer
HAVING count(state) = 1;
$$ LANGUAGE sql;


SELECT * FROM fnc_task3('2022-05-12');

-- 4) Найти процент успешных и неуспешных проверок за всё время
select * from mv_checks;


CREATE OR REPLACE FUNCTION fnс_task4()
RETURNS TABLE ("SuccessfulChecks" numeric, "UnsuccessfulChecks" numeric)
AS $$
    DECLARE
        Success integer := (SELECT count(*) FROM mv_checks ch WHERE ch.state = 'Success');
        Failure integer := (SELECT count(*) FROM mv_checks ch WHERE ch.state = 'Failure');
BEGIN
RETURN QUERY
SELECT  CASE
            WHEN (Success + Failure) != 0 THEN
                round(Success * 100 / (Success + Failure)::numeric)
            ELSE 0
            END AS "SuccessfulChecks",
        CASE
            WHEN (Success + Failure) != 0 THEN
                round(Failure * 100 / (Success + Failure)::numeric)
            ELSE 0
            END AS "UnsuccessfulChecks";
END;
$$ LANGUAGE plpgsql;

select * from fnc_task4();

-- 5) Посчитать изменение в количестве пир поинтов каждого пира по таблице TransferredPoints
CREATE OR REPLACE FUNCTION fnc_get_peer_points_change(IN peername text)
    RETURNS integer AS $$
BEGIN
    -- кол-во заработанных поинтов если пир есть в столбце checking_peer
RETURN (SELECT COALESCE((SELECT(sum(points_amount)) -- COALESCE если не нашлось такого пира, и после sum получился результат NULL
                         FROM transferred_points
                         WHERE checking_peer=peername
                         GROUP BY checking_peer), 0)
                   +
                   -- и кол-во потраченных поинтов если пир есть в столбце checkedpeer
               (SELECT COALESCE((SELECT(sum(points_amount)*-1) -- меняем знак
                                 FROM transferred_points
                                 WHERE checked_peer=peername
                                 GROUP BY checked_peer), 0))
);-- в результате получается сумма, если отрицательная то пир проверялся больше чем проверял
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fnс_task5()
RETURNS TABLE(peer varchar, PointsChange integer)
AS $$
BEGIN
RETURN QUERY
SELECT name AS Peer, fnc_get_peer_points_change(name) AS PointsChange
FROM (SELECT checking_peer AS name
      FROM transferred_points
      UNION DISTINCT
      SELECT checked_peer AS name
      FROM transferred_points ) AS names
ORDER BY Peer;
END;
$$ LANGUAGE plpgsql;

select * from fnc_task5();

-- 6) Посчитать изменение в количестве пир поинтов каждого пира по таблице, возвращаемой первой функцией из Part 3
CREATE OR REPLACE FUNCTION fnc_task6()
    RETURNS TABLE(Peer varchar, PointsChange integer)
AS $$
BEGIN
RETURN QUERY
SELECT name AS Peer, fnc_get_peer_points_change(name) AS PointsChange
FROM (SELECT "Peer1" AS name
      FROM fnc_task1()
      UNION DISTINCT
      SELECT "Peer2" AS name
      FROM fnc_task1()
     ) AS names
ORDER BY PointsChange DESC;
END;
$$ LANGUAGE plpgsql;

select * from fnc_task6();

-- 7) Определить самое часто проверяемое задание за каждый день
CREATE OR REPLACE FUNCTION fnc_get_max_count_task(IN date_ date)
    RETURNS integer
AS $$
BEGIN
RETURN (
    WITH checksinday AS
             (
                 SELECT c.date, c.task, count(*) AS count_
                 FROM checks c
                 GROUP BY 1, 2
                 ORDER BY 1
             )
    SELECT max(cd.count_)
    FROM checksinday cd
    WHERE cd.date=date_
);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fnc_task7()
    RETURNS TABLE("day" text, task varchar)
AS $$
BEGIN
RETURN QUERY
SELECT to_char(date, 'DD.MM.YYYY') AS day, t.task
FROM(SELECT c.date, c.task, count(*) AS count_
    FROM checks c
    GROUP BY 1, 2
    ORDER BY 1) AS t
WHERE count_=fnc_get_max_count_task(date)
ORDER BY 1, 2;
END;
$$ LANGUAGE plpgsql;

select * from fnc_task7();

-- 8) Определить длительность последней P2P проверки
CREATE OR REPLACE FUNCTION fnc_task8()
    RETURNS time
AS $$
DECLARE
    -- найти check последней проверки где есть старт и завершение
    check_ integer := ( SELECT p1.check_id
                            FROM p2p p1
                                    JOIN p2p p2 ON p2.check_id = p1.check_id AND p2.state='Start'
                            WHERE p1.state!='Start'
                            ORDER BY p1.time DESC
                            LIMIT 1);
    endtime time := (SELECT time FROM p2p
                     WHERE check_id=check_ AND state!='Start'
                     ORDER BY time DESC
                     LIMIT 1);
    starttime time := (SELECT time FROM p2p
                       WHERE check_id=check_ AND state='Start'
                       ORDER BY time DESC
                       LIMIT 1);
BEGIN
RETURN
    (SELECT endtime-starttime AS last_check_duration);
END;
$$ LANGUAGE plpgsql;

select * from fnc_task8() as last_check_duration;

-- 9) Найти всех пиров, выполнивших весь заданный блок задач и дату завершения последнего задания
CREATE OR REPLACE FUNCTION fnc_task9(IN blockname VARCHAR)
    RETURNS TABLE(peer varchar, "day" date)
AS $$
BEGIN
RETURN QUERY
    WITH cte AS (
            SELECT c.peer AS peer, task, c.date AS day, row_number() OVER (PARTITION BY c.peer) AS completed_task_counter
            FROM p2p p1
                     JOIN checks c ON c.id = p1.check_id
                     LEFT JOIN verter v1 ON c.id = v1.check_id AND (v1.state='Success' OR v1.state IS NULL)
            WHERE c.task LIKE (blockname||'%') and p1.state='Success'
              and p1.check_id in (SELECT p1.check_id
                                  FROM p2p p2
                                           JOIN checks c ON c.id = p2.check_id
                                           left JOIN verter v2 ON v2.check_id = v1.check_id AND (v1.state='Success' OR v1.state IS NULL)
                                  WHERE p2.state = 'Start' and p2.check_id = p1.check_id)
            GROUP BY c.peer, task, date
        )
SELECT cte.peer, cte.day
FROM cte
WHERE completed_task_counter = (SELECT count(*)
                                FROM tasks
                                WHERE tasks.title LIKE (blockname||'%'))
ORDER BY day DESC;
END;
$$ LANGUAGE plpgsql;

select * from fnc_task9('CPP');

--  10) Определить, к какому пиру стоит идти на проверку каждому обучающемуся

CREATE OR REPLACE FUNCTION fnc_task10 ()
    RETURNS TABLE(peer varchar, recommended_peer varchar)
AS $$
BEGIN
RETURN QUERY
    WITH w_tmp1 AS (SELECT p.nickname AS peer, f.peer2 AS friend, r.recommended_peer AS recommended_peer
                            FROM peers p
                            INNER JOIN friends f ON p.nickname = f.peer1
                            INNER JOIN recommendations r ON f.peer2 = r.peer AND p.nickname != r.recommended_peer
                            ORDER BY 1,2),
            w_tmp2 AS (SELECT w_tmp1.peer, w_tmp1.recommended_peer, count(w_tmp1.recommended_peer) AS count_of_recommends
                        FROM w_tmp1
                        GROUP BY 1,2
                        ORDER BY 1,2),
            w_tmp3 AS (SELECT w_tmp2.peer,
                              w_tmp2.recommended_peer,
                              w_tmp2.count_of_recommends,
                              ROW_NUMBER() OVER (PARTITION BY w_tmp2.peer ORDER BY w_tmp2.count_of_recommends DESC) AS num_of_row_for_each_peer
                        FROM w_tmp2)
SELECT w_tmp3.peer, w_tmp3.recommended_peer
FROM w_tmp3
WHERE w_tmp3.num_of_row_for_each_peer = 1;
END;
$$ LANGUAGE plpgsql;

select * from fnc_task10();

--  11) Определить процент пиров, которые:Приступили к блоку 1,Приступили к блоку 2, Приступили к обоим, Не приступили ни к одному
CREATE OR REPLACE FUNCTION PeersStartedBlock("block" varchar)
    RETURNS table("Peer" varchar)
AS $$
SELECT DISTINCT ch.peer
FROM checks ch
WHERE ch.task LIKE "block" || '%'
    $$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION fnc_task11(IN block1 VARCHAR, IN block2 VARCHAR)
    RETURNS TABLE(StartedBlock1 integer, StartedBlock2 integer, StartedBothBlocks integer, DidntStartAnyBlock integer)
AS $$
    DECLARE
        StartedBlock1 INTEGER := (SELECT count(*) FROM PeersStartedBlock("block1"));
        StartedBlock2 INTEGER := (SELECT count(*) FROM PeersStartedBlock("block2"));
        StartedBothBlocks INTEGER := (SELECT count(*) FROM (
                                                           SELECT "Peer"  FROM PeersStartedBlock("block1")
                                                           INTERSECT
                                                           SELECT "Peer"  FROM PeersStartedBlock("block2")
                                                       ) AS res);
        DidntStartAnyBlock INTEGER := (SELECT count(*) FROM (
                                                            SELECT nickname FROM peers
                                                            EXCEPT
                                                            (SELECT "Peer" FROM PeersStartedBlock("block1")
                                                             UNION
                                                             SELECT "Peer" FROM PeersStartedBlock("block2"))
                                                        ) AS res1);
        AllPeers INTEGER := (SELECT count(*) FROM peers);
BEGIN
RETURN QUERY
SELECT StartedBlock1 * 100 / AllPeers AS StartedBlock1,
       StartedBlock2 * 100 / AllPeers AS StartedBlock2,
       StartedBothBlocks * 100 / AllPeers AS StartedBothBlocks,
       DidntStartAnyBlock * 100 / AllPeers AS DidntStartAnyBlock;
END;
$$ LANGUAGE plpgsql;

select * from fnc_task11('D0', 'C');

-- 12) Определить N пиров с наибольшим числом друзей
CREATE OR REPLACE FUNCTION fnc_task12(IN fLIMIT integer)
    RETURNS TABLE(peer varchar, FriendsCount integer)
AS $$
BEGIN
RETURN QUERY
SELECT peer1 AS "Peer", count(*)::integer AS FriendsCount
FROM (SELECT peer1 FROM friends
      UNION ALL
      SELECT peer2 FROM friends) AS res
GROUP BY peer1
ORDER BY FriendsCount DESC
    LIMIT fLIMIT;
END;
$$ LANGUAGE plpgsql;

select * from fnc_task12(7);

-- 13) Определить процент пиров, которые когда-либо успешно проходили проверку в свой день рождения
UPDATE peers
SET birthday = '1994-11-10'
WHERE nickname = 'duck' OR nickname = 'jersey' OR nickname = 'class';


CREATE OR REPLACE FUNCTION fnc_ChecksCountOnBirthday(fstate varchar)
    RETURNS integer
AS $$
SELECT count(*) AS count_
FROM mv_checks ch JOIN peers p ON p.nickname = ch.peer
WHERE substring(ch.date::text, 5) = substring(p.birthday::text, 5) AND ch.state = fstate
    $$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION fnc_task13()
    RETURNS TABLE(SuccessfulChecks numeric, UnsuccessfulChecks numeric)
AS $$
DECLARE
    s integer := (SELECT * FROM fnc_ChecksCountOnBirthday('Success'));
    f integer := (SELECT * FROM fnc_ChecksCountOnBirthday('Failure'));
BEGIN
RETURN QUERY
SELECT CASE
           WHEN (s + f) != 0 THEN round(s * 100 / (s + f)::numeric)
           ELSE 0
           END AS "SuccessfulChecks",
       CASE
           WHEN (s + f) != 0 THEN round(f * 100 / (s + f)::numeric)
           ELSE 0
           END AS "UnsuccessfulChecks";
END;
$$ LANGUAGE plpgsql;

select * from fnc_task13();

UPDATE peers
SET birthday = '1999-09-18'
WHERE nickname = 'duck';

UPDATE peers
SET birthday = '1984-04-19'
WHERE nickname = 'jersey';

UPDATE peers
SET birthday = '1993-02-21'
WHERE nickname = 'class';

-- 14) Определить кол-во XP, полученное в сумме каждым пиром
CREATE OR REPLACE FUNCTION fnc_task14 ()
    RETURNS TABLE(peer varchar, xp bigint)
AS $$
BEGIN
RETURN QUERY
SELECT tmp.peer, sum(maxpoint) AS xp
FROM (SELECT p.nickname AS peer, t.title AS project, max(xp.xp_amount) AS maxpoint
      FROM xp INNER JOIN checks ch ON ch.id = xp.check_id
              INNER JOIN peers p ON p.nickname = ch.peer
              INNER JOIN tasks t ON ch.task = t.title
      GROUP BY 1,2
      ORDER BY 1,2) tmp
GROUP BY tmp.peer
ORDER BY 2 DESC;
END;
$$ LANGUAGE plpgsql;

select * from fnc_task14();

-- 15) Определить всех пиров, которые сдали заданные задания 1 и 2, но не сдали задание 3
CREATE OR REPLACE FUNCTION fnc_PeerCompletedTasks(fpeer text, ftask text)
    RETURNS bool
AS $$
SELECT EXISTS (SELECT ch.peer
               FROM mv_checks ch
               WHERE ch.peer = fpeer AND ch.task = ftask AND ch.state = 'Success')
           $$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION fnc_task15(IN firstT text, IN secondT text, IN third text)
    RETURNS TABLE(peer varchar)
AS $$
BEGIN
RETURN QUERY
SELECT DISTINCT p.nickname
FROM peers p JOIN checks ch ON ch.peer = p.nickname
WHERE fnc_PeerCompletedTasks(p.nickname, firstT)
  AND fnc_PeerCompletedTasks(p.nickname, secondT)
  AND NOT fnc_PeerCompletedTasks(p.nickname, third);
END;
$$ LANGUAGE plpgsql;

select * from fnc_task15('C4_Math', 'C5_Decimal', 'DO1_Linux');

-- 16) Используя рекурсивное обобщенное табличное выражение, для каждой задачи вывести кол-во предшествующих ей задач
CREATE OR REPLACE FUNCTION recursiveCountParent(tasks_ text)
    RETURNS integer
AS $$
    WITH RECURSIVE test AS (
        SELECT title, parent_task, 0 AS level
        FROM tasks
        WHERE title = tasks_
        UNION ALL
        SELECT t.title, t.parent_task, test.level + 1
        FROM tasks t
                 JOIN test ON t.title = test.parent_task
    )
SELECT max(test.level) FROM test
                                $$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION fnc_task16()
    RETURNS TABLE(title varchar, number_of_tasks integer )
AS $$
BEGIN
RETURN QUERY
SELECT t.title, recursiveCountParent(t.title) FROM tasks t;
END;
$$ LANGUAGE plpgsql;

select * from fnc_task16();

-- 17) Найти "удачные" для проверок дни. День считается "удачным", если в нем есть хотя бы N идущих подряд успешных проверки
CREATE OR REPLACE FUNCTION fnc_task17(IN N integer)
    RETURNS TABLE(lucky_day date)
AS $$
BEGIN
RETURN QUERY
    WITH AllGroup AS
            (
                SELECT  "id",
                        "task",
                        "state",
                        "date",
                        SUM(CASE WHEN "state" = prev THEN 0 ELSE 1 END) OVER(ORDER BY "id") AS grp
                FROM (SELECT *, LAG("state") OVER(ORDER BY "id") AS prev
                        FROM mv_checks) AS res
            )
SELECT "date"::date
FROM ( SELECT "date", count(*) AS CountChecks
       FROM AllGroup ag JOIN xp ON xp.check_id = ag.id
                        JOIN tasks t ON t.title = ag."task"
       WHERE ag."state" = 'Success' AND xp.xp_amount > t.max_xp * 0.8
       GROUP BY grp, "date"
     ) AS res
GROUP BY "date"
HAVING max(CountChecks) >= N;
END;
$$ LANGUAGE plpgsql;

select * from fnc_task17(8);

-- 18) Определить пира с наибольшим числом выполненных заданий
CREATE OR REPLACE FUNCTION fnc_task18()
    RETURNS TABLE(peer varchar, max_complete_task bigint)
AS $$
BEGIN
RETURN QUERY
    WITH CompletedTask AS (
            SELECT ch.peer, count(*) AS count_
            FROM mv_checks ch
            WHERE ch.state = 'Success'
            GROUP BY ch.peer
        )
SELECT ct.peer AS "Peer", count_ AS "Tasks"
FROM CompletedTask ct
WHERE ct.count_ = (SELECT max(count_) FROM CompletedTask);
END;
$$ LANGUAGE plpgsql;

select * from fnc_task18();

-- 19) Определить пира с наибольшим количеством XP
CREATE OR REPLACE FUNCTION fnc_task19 ()
    RETURNS TABLE(peer varchar, max_xp bigint)
AS $$
BEGIN
RETURN QUERY
SELECT p.nickname AS Peer, sum(xp_amount) AS XP
FROM checks ch
         INNER JOIN xp ON ch.id = xp.check_id
         INNER JOIN peers p ON p.nickname = ch.peer
GROUP BY p.nickname
HAVING sum(xp_amount) = (SELECT sum(xp_amount)
                         FROM checks ch
                                  INNER JOIN xp ON ch.id = xp.check_id
                                  INNER JOIN peers p ON p.nickname = ch.peer
                         GROUP BY p.nickname
                         ORDER BY 1 DESC LIMIT 1);
END;
$$ LANGUAGE plpgsql;

select * from fnc_task19();

-- 20) Определить пира, который провел сегодня в кампусе больше всего времени
CREATE OR REPLACE FUNCTION fnc_task20 ()
    RETURNS TABLE (peer varchar)
AS $$
BEGIN
RETURN QUERY
    WITH intime AS(
                    SELECT id, tt1.peer, "time"
                    FROM time_tracking tt1
                    WHERE state = 1 AND "date" = now()::date),
                 outtime AS(
                     SELECT id, tt2.peer, "time"
                     FROM time_tracking tt2
                     WHERE state = 2 AND "date" = now()::date),
                 JOINtable AS (
                     SELECT DISTINCT ON (i.id) i.id AS id1, i.peer AS peer1, i."time" AS time1, o.id AS id2, o.peer AS peer2, o."time" AS time2
                     FROM intime i INNER JOIN outtime o ON i.peer = o.peer AND i."time" < o."time"
                    ORDER BY 1,2,3,6),
                peerandmaxtime AS (
                    SELECT peer1 AS peer
                    FROM JOINtable
                    GROUP BY peer1
                    HAVING (sum(time2 - time1)::time) = (SELECT (sum(time2 - time1)::time) AS time3
                    FROM JOINtable
                    GROUP BY peer1
                    ORDER BY 1 DESC LIMIT 1))
SELECT * FROM peerandmaxtime;
END;
$$ LANGUAGE plpgsql;

select * from fnc_task20();

-- 21) Определить пиров, приходивших раньше заданного времени не менее N раз за всё время-
CREATE OR REPLACE FUNCTION fnc_task21(time_ time, mincount integer)
    RETURNS TABLE (peer varchar)
AS $$
BEGIN
RETURN QUERY
SELECT res.peer
FROM(SELECT tt.peer, "date", min("time")
     FROM time_tracking tt
     WHERE "state" = 1 AND "time" < time_
     GROUP BY 1, 2
     ORDER BY 2) AS res
GROUP BY res.peer
HAVING count(*) >= mincount;
END;
$$ LANGUAGE plpgsql;

select * from fnc_task21('13:00:00', 2);

-- 22) Определить пиров, выходивших за последние N дней из кампуса больше M раз
CREATE OR REPLACE FUNCTION fnc_task22(Ndays integer, mincount integer)
    RETURNS TABLE (peer varchar)
AS $$
BEGIN
RETURN QUERY
SELECT res.peer
FROM (SELECT tt.peer, "date", count(*) - 1 AS count_
      FROM time_tracking tt
      WHERE "state" = 1 AND "date" > (now()::date - Ndays)
      GROUP BY 1, 2
      ORDER BY 2) AS res
GROUP BY res.peer
HAVING sum(count_) > mincount;
END;
$$ LANGUAGE plpgsql;

select * from fnc_task22(2, 1);

-- 23) Определить пира, который пришел сегодня последним
CREATE OR REPLACE FUNCTION fnc_task23()
    RETURNS TABLE (peer varchar)
AS $$
BEGIN
RETURN QUERY
SELECT res.peer
FROM (SELECT tt.peer, "date", min("time")
      FROM time_tracking tt
      WHERE "state" = 1 AND "date" = now()::date
      GROUP BY 1, 2
      ORDER BY 3 DESC
          LIMIT 1) AS res;
END;
$$ LANGUAGE plpgsql;

select * from fnc_task23();

-- 24) Определить пиров, которые выходили вчера из кампуса больше чем на N минут
CREATE OR REPLACE FUNCTION fnc_task24(N integer)
    RETURNS TABLE (peer varchar)
AS $$
BEGIN
RETURN QUERY
    WITH in_ AS (
            SELECT id, tt.peer, "date", "time"
            FROM time_tracking tt
            WHERE tt.state = 1 AND "date" = current_date - 1
              AND NOT tt.time = ( SELECT min("time")
                                  FROM time_tracking tt2
                                  WHERE tt2.date = tt.date AND tt2.peer = tt.peer)
            ORDER BY 2, 4
        ), out_ AS(
            SELECT id, tt.peer, "date", "time"
            FROM time_tracking tt
            WHERE tt.state = 2 AND "date" = current_date - 1
              AND NOT tt.time = ( SELECT max("time")
                                  FROM time_tracking tt2
                                  WHERE tt2.date = tt.date AND tt2.peer = tt.peer)
            ORDER BY 2, 4
        ), InAndOut AS(
            SELECT DISTINCT ON (in_.id) in_.id, in_.peer, out_.time AS out_, in_.time AS in_
            FROM in_
                     JOIN out_ ON in_.peer = out_.peer AND in_.date = out_.date
            WHERE out_.time < in_.time
        )
SELECT InAndOut.peer
FROM InAndOut
GROUP BY InAndOut.peer
HAVING sum(InAndOut.in_ - InAndOut.out_) > make_time(N / 60, N - N / 60 * 60, 0.);
END;
$$ LANGUAGE plpgsql;

select * from fnc_task24(120);

-- 25) Определить для каждого месяца процент ранних входов
CREATE OR REPLACE FUNCTION countVisit(peer_ text, mintime time DEFAULT '24:00:00')
    RETURNS integer
AS $$
SELECT count(*) FROM ( SELECT tt.peer, tt.date
                       FROM time_tracking tt
                       WHERE tt.peer = peer_
                       GROUP BY 1, 2
                       HAVING min("time") < mintime) AS res
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION fnc_task25()
    RETURNS TABLE("month" text, early_entries bigint)
AS $$
BEGIN
RETURN QUERY
    WITH Months AS (
                    SELECT gs::date AS list_date
                    FROM generate_series('2000-01-31', '2000-12-31', interval '1 month') AS gs),
    VisitsInMonthOfBirth AS (
                    SELECT  TO_CHAR(list_date, 'Month') AS name_month,
                            SUM(countVisit(p.nickname::text)) AS "AllVisits",
                            SUM(countVisit(p.nickname::text, '12:00:00')) AS "EarlyVisits"
                    FROM Months
                            LEFT JOIN peers p ON EXTRACT(MONTH FROM list_date) = EXTRACT(MONTH FROM p.birthday::date)
                    GROUP BY list_date)
SELECT name_month,  CASE WHEN "AllVisits" = 0
                    THEN 0
                    ELSE ("EarlyVisits" * 100 / "AllVisits")
                    END AS "EarlyEntries"
FROM VisitsInMonthOfBirth
ORDER BY to_date(name_month, 'Mon');
END;
$$ LANGUAGE plpgsql;

select * from fnc_task25();

