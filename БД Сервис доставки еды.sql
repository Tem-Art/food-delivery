-- ТОП-5 клиентов, сделавших больше всего заказов за всё время.

select u.first_name || ' ' || u.last_name as "Имя клиента", count(o.order_id) as "Количество заказов"
from users u
join orders o on u.user_id = o.user_id
group by u.user_id
order by count(o.order_id) desc
limit 5;

-------------------------------------------------------------------------------------------------------

-- Данные о последнем платеже каждого клиента.

-- Используем оконную функцию row_number() для получения последнего платежа каждого клиента
with ranked_payments as (
    select 
        user_id, transaction_id, transaction_date, amount,
        row_number() over (partition by user_id order by transaction_date desc) as rn  -- Нумерация по убыванию даты
    from transactions
)
-- Оставляем только последнюю оплату на каждого пользователя
select 
    user_id, transaction_id, transaction_date, amount
from ranked_payments
where rn = 1
order by user_id;

-------------------------------------------------------------------------------------------------------

-- Расчет показателей для каждого клиента:
-- • количество заказов
-- • общая сумма платежей (округлённое до целого числа)
-- • минимальная и максимальная сумма заказа.

-- Выводим ФИО клиента и его метрики
select u.first_name || ' ' || u.last_name as "Имя клиента",
       o_data.total_orders,                         -- Кол-во заказов
       p_data.total_spent,                          -- Суммарная сумма заказов
       p_data.min_payment,                          -- Минимальный платёж
       p_data.max_payment                           -- Максимальный платёж
from users u
-- Кол-во заказов по каждому клиенту
join (
    select user_id, count(order_id) as total_orders
    from orders
    group by user_id
) o_data on u.user_id = o_data.user_id
-- Метрики платежей по каждому клиенту
join (
    select user_id,
           round(sum(amount)) as total_spent,
           min(amount) as min_payment,
           max(amount) as max_payment
    from transactions
    group by user_id
) p_data on u.user_id = p_data.user_id;

-------------------------------------------------------------------------------------------------------
	
--Популярность и прибыльность блюд.

-- Выводим название блюда, количество заказов и общую выручку
select m.item_name,
       stats.total_orders,
       stats.total_revenue
from menu m
-- Собираем статистику по каждому блюду
left join (
    select menu_item_id,
           count(order_id) as total_orders,    -- Сколько раз блюдо заказывали
           sum(amount) as total_revenue        -- Сколько денег оно принесло
    from order_items
    group by menu_item_id
) stats on m.menu_item_id = stats.menu_item_id;

-------------------------------------------------------------------------------------------------------	

-- Расчет количества собранных заказов каждым сотрудником, для вычисления премии.
-- Добавлена колонка "Премия" (если количество превышает 2000, то значение в колонке "Да", иначе "Нет").

-- Считаем количество собранных заказов каждым сотрудником за последний месяц
select 
    s.staff_id,
    count(o.order_id) as "Количество заказов",
    -- Премия, если сотрудник собрал больше 2000 заказов за месяц
    case when count(o.order_id) > 2000 then 'Да' else 'Нет' end as "Премия"
from staff s
join orders o on s.staff_id = o.staff_id
-- Учитываем только заказы за последний месяц
where o.order_date >= current_date - interval '1 month'
group by s.staff_id;

-------------------------------------------------------------------------------------------------------

-- Вывод клиентов для каждого города, попадающих под условия:
-- • наибольшее количество заказов
-- • заказов на самую большую сумму
-- • клиент, который последним сделал заказ.

-- Агрегаты по клиентам
with cte1 as (
    select 
        o.user_id,
        count(*) as order_count,                -- Количество заказов клиента
        sum(t.amount) as total_amount,          -- Общая сумма трат
        max(o.order_date) as last_order         -- Дата последнего заказа
    from orders o
    join transactions t on o.order_id = t.order_id
    group by o.user_id
),

-- Сопоставляем клиентов с городами и находим лидеров по каждому критерию
cte2 as (
    select 
        u.user_id,
        concat(u.last_name, ' ', u.first_name) as full_name,
        a.city,                                  
        order_count,
        total_amount,
        last_order,
        -- Клиент с наибольшим числом заказов в городе
        case when order_count = max(order_count) over (partition by a.city)
             then full_name end as top_orders,
        -- Клиент с наибольшей суммой заказов в городе
        case when total_amount = max(total_amount) over (partition by a.city)
             then full_name end as top_spenders,
        -- Клиент, сделавший самый последний заказ в городе
        case when last_order = max(last_order) over (partition by a.city)
             then full_name end as last_customers
    from cte1
    join users u on u.user_id = cte1.user_id
    join addresses a on a.address_id = u.address_id
)

-- Для каждого города выводим по одному лидеру по каждому из трёх критериев
select 
    city,
    string_agg(distinct top_orders, ', ') as "Больше всего заказов", -- Разделитель на случай "ничьи"
    string_agg(distinct top_spenders, ', ') as "Больше всего потратил",
    string_agg(distinct last_customers, ', ') as "Сделал последний заказ"
from cte2
group by city;

-------------------------------------------------------------------------------------------------------

-- Вывод аналитических показателей для каждого ресторана:
-- • день с наибольшим количеством заказов и количество заказов в этот день
-- • день с наименьшей выручкой и сумма выручки в этот день

-- CTE: определяем день с наибольшим количеством заказов по каждому ресторану
with max_orders_per_restaurant as (
    select 
        m.restaurant_id,                        -- ID ресторана
        o.order_date::date as day,              -- День, в который оформлены заказы
        count(o.order_id) as metric_value,      -- Количество заказов в этот день
        row_number() over (
            partition by m.restaurant_id 
            order by count(o.order_id) desc     -- Сортировка по убыванию количества
        ) as rn
    from orders o
    join menu_items m on o.menu_item_id = m.menu_item_id  -- Привязка заказа к ресторану через блюдо
    group by m.restaurant_id, o.order_date::date
),

-- CTE: определяем день с наименьшей суммой выручки по каждому ресторану
min_sales_per_restaurant as (
    select 
        s.restaurant_id,
        t.transaction_date::date as day,        -- День проведения транзакции
        sum(t.amount) as metric_value,          -- Сумма выручки за день
        row_number() over (
            partition by s.restaurant_id 
            order by sum(t.amount)              -- Сортировка по возрастанию суммы
        ) as rn
    from transactions t
    join staff s on t.staff_id = s.staff_id     -- Привязка оплаты к ресторану через сотрудника
    group by s.restaurant_id, t.transaction_date::date
)

-- Объединяем результаты двух CTE: макс. заказы и мин. выручка
select 
    restaurant_id,
    day,
    metric_value,
    'Макс. заказы' as metric_type
from max_orders_per_restaurant
where rn = 1

union all

select 
    restaurant_id,
    day,
    metric_value,
    'Мин. выручка' as metric_type
from min_sales_per_restaurant
where rn = 1;

-------------------------------------------------------------------------------------------------------

-- Оптимизация чужого запроса.

-- Цель: найти пользователей, которые чаще всего заказывали блюда с меткой "Острое"

-- ИЗНАЧАЛЬНЫЙ ЗАПРОС

explain analyze -- 8600.22 / 38.315 сек
select distinct u.first_name  || ' ' || u.last_name as name, 
    count(ren.iid) over (partition by u.user_id)
from users u
full outer join 
    (select *, o.order_item_id as iid, inv.tag_string as sfs, o.user_id as uid
     from orders o 
     full outer join 
        (select *, unnest(m.tags) as tag_string
         from order_items oi
         full outer join menu_items m on m.menu_item_id = oi.menu_item_id) as inv 
     on o.order_item_id = inv.order_item_id) as ren 
on ren.uid = u.user_id 
where ren.sfs like '%Spicy%'
order by count desc

-- Проблема: большое количество сортировок, тяжёлые объединения, распаковка массива тегов.
-- Это видно в узлах: PROJECTSET 3.22 ms, NESTED LOOP (Left join) 11.51 ms, SORT (по u.user_id) 3.84ms,
-- SORT 4.3ms (по count(order_item_id) OVER (?) DESC, (((u.first_name || ' ' || u.last_name)))).

-- ОПТИМИЗИРОВАННЫЙ ЗАПРОС 

explain analyze -- 652 / 8 сек
select u.first_name || ' ' || u.last_name, count(o.order_id)
from orders o
right join order_items oi on 
    o.order_item_id = oi.order_item_id and 
    oi.menu_item_id in (
        select menu_item_id
        from menu_items
        where tags && array['Spicy'])
join users u on u.user_id = o.user_id
group by u.user_id
order by count desc