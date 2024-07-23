create table resume (
	resume_id serial primary key,
	skills text,
	additional_info text
	);
	
create table personal_info (
	info_id serial primary key,
	name varchar(20) NOT NULL,
	second_name varchar(20) NOT NULL,
	middle_name varchar(20),
	birth_date date NOT NULL,
	resume integer,
	foreign key (resume) references resume(resume_id) ON DELETE RESTRICT);

CREATE TYPE vacancy_status AS ENUM (
    'open',       -- Вакансия открыта
    'closed',     -- Вакансия закрыта
    'on_hold'   -- Вакансия приостановлена
);
create table vacancy (
	vacancy_id serial primary key,
	vacancy_name varchar(50) NOT NULL,
	vac_description text,
	open_date date,
	close_date date,
	status vacancy_status NOT NULL,
	department integer NOT NULL,
	CHECK (open_date <= close_date)
); 

create table candidate (
	candidate_id serial primary key,
	personal_info integer NOT NULL,
	vacancy integer NOT NULL,
	foreign key (personal_info) references personal_info(info_id) ON DELETE RESTRICT,
	foreign key (vacancy) references vacancy(vacancy_id) ON DELETE RESTRICT);
	
CREATE TYPE candidate_status AS ENUM ('applied', 'interviewing', 'offered', 'rejected');
create table status (
	status_id serial primary key,
	candidate integer NOT NULL,
	status candidate_status NOT NULL,
	change_date date NOT NULL,
	additional_info text,
	foreign key (candidate) references candidate(candidate_id) ON DELETE RESTRICT);
	
CREATE TYPE level_education AS ENUM (
    'no_degree',  -- Без образования или школьное образование
    'high_school',  -- Средняя школа
    'associate',  -- Диплом младшего специалиста или аналогичный
    'bachelor',  -- Бакалавриат
    'master',  -- Магистратура
    'doctorate',  -- Докторская степень
    'other'  -- Другие или специфические квалификации
);
create table education (
	education_id serial primary key,
	level level_education NOT NULL,
	institution varchar(50),
	speciality varchar(50),
	graduation smallint,
	resume integer NOT NULL,
	foreign key (resume) references resume(resume_id) ON DELETE cascade);
	
create table experience (
	experience_id serial primary key,
	workplace varchar(50),
	job varchar(50),
	year_beginning smallint,
	year_ending smallint,
	resume integer NOT NULL,
	foreign key (resume) references resume(resume_id) ON DELETE cascade,
	CHECK (year_beggining <= year_ending));
	
create table job (
	job_id serial primary key,
	job_title varchar(50) NOT NULL UNIQUE,
	status boolean NOT NULL DEFAULT TRUE); -- 1 - актив, 0 - не актив
	
create table department (
	department_id serial primary key,
	department_name varchar(30) NOT NULL UNIQUE,
	head integer,
	status boolean NOT NULL DEFAULT TRUE); -- 1 - актив, 0 - не актив

CREATE TYPE type_of_employment AS ENUM (
    'full_time',  -- Полная занятость
    'part_time',  -- Частичная занятость
    'contract',   -- Договор/контракт
    'temporary',  -- Временная работа
    'internship', -- Стажировка
    'freelance'   -- Фриланс
);	
create table offer (
	offer_id serial primary key,
	candidate integer NOT NULL,
	offer_date date NOT NULL,
	salary money,
	type_of_employment type_of_employment,
	job integer NOT NULL,
	department integer NOT NULL,
	foreign key (candidate) references candidate(candidate_id) ON DELETE RESTRICT,
	foreign key (job) references job(job_id) ON DELETE RESTRICT,
	foreign key (department) references department(department_id) ON DELETE RESTRICT);
	
create table employee (
	employee_id serial primary key,
	offer integer NOT NULL UNIQUE,
	status boolean NOT NULL DEFAULT TRUE,
	current_job integer,
	current_department integer,
	current_salary money,
	foreign key (current_job) references job(job_id) ON DELETE RESTRICT,
	foreign key (current_department) references department(department_id) ON DELETE RESTRICT,
	foreign key (offer) references offer(offer_id) ON DELETE RESTRICT);
	

CREATE TYPE change_type AS ENUM (
    'promotion',  -- Повышение
    'demotion',   -- Понижение
    'transfer',   -- Перевод
    'termination'  -- Увольнение
);
create table orders (
	order_id serial primary key,
	employee_id integer NOT NULL,
	type_of_change change_type NOT NULL,
	date date NOT NULL DEFAULT CURRENT_DATE,
	new_salary money,
	new_job integer,
	new_department integer,
	previous_salary money,
	previous_job integer,
	previous_department integer,
	additional_info text,
	foreign key (employee_id) references employee(employee_id) ON DELETE RESTRICT,
	foreign key (new_job) references job(job_id) ON DELETE RESTRICT,
	foreign key (previous_job) references job(job_id) ON DELETE RESTRICT,
	foreign key (new_department) references department(department_id) ON DELETE RESTRICT,
	foreign key (previous_department) references department(department_id) ON DELETE RESTRICT
	);

ALTER TABLE department
  ADD CONSTRAINT fk_employee_department
  FOREIGN KEY (head) 
  REFERENCES employee(employee_id);

ALTER TABLE vacancy
  ADD CONSTRAINT fk_vacancy_department
  FOREIGN KEY (department) 
  REFERENCES department(department_id);
	
CREATE INDEX idx_personal_info_resume ON personal_info(resume);
CREATE INDEX idx_candidate_personal_info ON candidate(personal_info);
CREATE INDEX idx_candidate_vacancy ON candidate(vacancy);
CREATE INDEX idx_offer_candidate ON offer(candidate);
CREATE INDEX idx_offer_job ON offer(job);
CREATE INDEX idx_offer_department ON offer(department);
CREATE INDEX idx_order_employee_id ON orders(employee_id);
CREATE INDEX idx_order_date ON orders(date);

-- Функция для автоматического создания записи в таблице "status"
CREATE OR REPLACE FUNCTION create_initial_status() 
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO status (candidate, status, change_date, additional_info)
    VALUES (NEW.candidate_id, 'applied', NOW(), 'Automatically created initial status');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггер для автоматического создания статуса при добавлении нового оффера
CREATE TRIGGER trg_create_initial_status
AFTER INSERT ON candidate
FOR EACH ROW EXECUTE FUNCTION create_initial_status();

-- Функция для автоматического изменения записи в таблице "status" на hired
CREATE OR REPLACE FUNCTION change_hired_status() 
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO status (candidate, status, change_date, additional_info)
    VALUES (NEW.candidate, 'offered', NOW(), 'Automatically created employment status');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггер для автоматического создания статуса при добавлении нового оффера
CREATE TRIGGER trg_change_hired_status
AFTER INSERT ON offer
FOR EACH ROW EXECUTE FUNCTION change_hired_status();

-- Функция для закрытия вакансии при найме кандидата
CREATE OR REPLACE FUNCTION close_vacancy_on_hire() 
RETURNS TRIGGER AS $$
DECLARE
    v_vacancy_id INT;
BEGIN
    -- Находим идентификатор вакансии через таблицу candidate
    SELECT vacancy INTO v_vacancy_id
    FROM candidate
    WHERE candidate_id = NEW.candidate;
    
    -- Обновляем статус вакансии
    IF (NEW.status = 'offered' AND v_vacancy_id IS NOT NULL) THEN
        UPDATE vacancy 
        SET status = 'closed' 
        WHERE vacancy_id = v_vacancy_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггер для закрытия вакансии при найме кандидата
CREATE TRIGGER trg_close_vacancy_on_hire
AFTER INSERT ON status
FOR EACH ROW EXECUTE FUNCTION close_vacancy_on_hire();

-- Функция для проверки статуса работы и департамента перед вставкой в `order`
CREATE OR REPLACE FUNCTION check_active_job_and_department_before_insert() 
RETURNS TRIGGER AS $$
BEGIN
    -- Проверяем, что новая работа активна
    IF (NEW.new_job IS NOT NULL) THEN
        PERFORM job_id FROM job WHERE job_id = NEW.new_job AND status = TRUE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Нельзя назначить неактивную работу!';
        END IF;
    END IF;

    -- Проверяем, что новый департамент активен
    IF (NEW.new_department IS NOT NULL) THEN
        PERFORM department_id FROM department WHERE department_id = NEW.new_department AND status = TRUE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Нельзя назначить в неактивный департамент!';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггер, который активируется перед вставкой в `order`
CREATE TRIGGER trg_check_active_job_and_department_before_insert
BEFORE INSERT ON orders
FOR EACH ROW EXECUTE FUNCTION check_active_job_and_department_before_insert();

-- Функция, которая устанавливает статус сотрудника в 0 при увольнении
CREATE OR REPLACE FUNCTION set_employee_status_to_terminated() 
RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.type_of_change = 'termination') THEN
        UPDATE employee 
        SET status = FALSE, current_job = NULL, current_department = NULL, current_salary = NULL
        WHERE employee_id = NEW.employee_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггер, который устанавливает статус сотрудника в 0 после вставки в "orders"
CREATE TRIGGER trg_set_employee_status_to_terminated
AFTER INSERT ON orders
FOR EACH ROW EXECUTE FUNCTION set_employee_status_to_terminated();


-- Функция для автоматического создания записи в таблице "employee" после получения offer
CREATE OR REPLACE FUNCTION create_employee() 
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO employee (offer, current_job, current_department, current_salary)
    VALUES (NEW.offer_id, NEW.job, NEW.department, NEW.salary);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггер для автоматического создания записи в таблице "employee" после получения offer
CREATE TRIGGER trg_create_employee
AFTER INSERT ON offer
FOR EACH ROW EXECUTE FUNCTION create_employee();

-- Функция для проверки соответствия типа изменения реальным изменениям
CREATE OR REPLACE FUNCTION check_type_of_change() 
RETURNS TRIGGER AS $$
BEGIN
    -- Проверка соответствия "promotion" с увеличением зарплаты
    IF (NEW.type_of_change = 'promotion') THEN
        IF (NEW.new_salary <= NEW.previous_salary) THEN
            RAISE EXCEPTION 'Повышение должно сопровождаться увеличением зарплаты!';
        END IF;
    END IF;

    -- Проверка соответствия "demotion" с уменьшением зарплаты
    IF (NEW.type_of_change = 'demotion') THEN
        IF (NEW.new_salary >= NEW.previous_salary) THEN
            RAISE EXCEPTION 'Понижение должно сопровождаться уменьшением зарплаты!';
        END IF;
    END IF;

    -- Проверка соответствия "transfer" с изменением отдела
    IF (NEW.type_of_change = 'transfer') THEN
        IF (NEW.new_department = NEW.previous_department) THEN
            RAISE EXCEPTION 'Перевод должен включать смену отдела!';
        END IF;
    END IF;

    -- Проверка соответствия "termination" с удалением сотрудника
    IF (NEW.type_of_change = 'termination') THEN
        IF (NEW.new_job IS NOT NULL OR NEW.new_salary IS NOT NULL OR NEW.new_department IS NOT NULL) THEN
            RAISE EXCEPTION 'При увольнении поля new_job, new_salary и new_department должны быть NULL!';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггер для проверки типа изменения перед вставкой в "orders"
CREATE TRIGGER trg_check_type_of_change
BEFORE INSERT ON orders
FOR EACH ROW EXECUTE FUNCTION check_type_of_change();


-- Функция, которая предотвращает изменение статуса работы на "неактивный" при наличии сотрудников
CREATE OR REPLACE FUNCTION prevent_deactivating_job_with_employees() 
RETURNS TRIGGER AS $$
BEGIN
    -- Если статус изменяется на 0, проверить, есть ли сотрудники в этой должности
    IF (NEW.status = FALSE) THEN
        PERFORM employee_id FROM employee WHERE current_job = OLD.job_id;
        IF FOUND THEN
            RAISE EXCEPTION 'Нельзя деактивировать работу, если там работают люди!';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггер для предотвращения деактивации должности с работающими сотрудниками
CREATE TRIGGER trg_prevent_deactivating_job_with_employees
BEFORE UPDATE ON job
FOR EACH ROW EXECUTE FUNCTION prevent_deactivating_job_with_employees();

-- Функция, которая предотвращает изменение статуса департамента на "неактивный" при наличии сотрудников
CREATE OR REPLACE FUNCTION prevent_deactivating_department_with_employees() 
RETURNS TRIGGER AS $$
BEGIN
    -- Если статус изменяется на 0, проверить, есть ли сотрудники в этом отделе
    IF (NEW.status = FALSE) THEN
        PERFORM employee_id FROM employee WHERE current_department = OLD.department_id;
        IF FOUND THEN
            RAISE EXCEPTION 'Нельзя деактивировать отдел, если там работают люди!';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггер для предотвращения деактивации департамента с работающими сотрудниками
CREATE TRIGGER trg_prevent_deactivating_department_with_employees
BEFORE UPDATE ON job
FOR EACH ROW EXECUTE FUNCTION prevent_deactivating_department_with_employees();

-- Функция для обновления полей "employee" после вставки в "orders"
CREATE OR REPLACE FUNCTION update_employee_info_from_order() 
RETURNS TRIGGER AS $$
BEGIN
    -- Обновляем текущую работу, департамент и зарплату, если приказ не увольнение
    IF (NEW.type_of_change <> 'termination') THEN
        UPDATE employee
        SET current_job = NEW.new_job,
            current_department = NEW.new_department,
            current_salary = NEW.new_salary
        WHERE employee_id = NEW.employee_id;
	END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггер, который обновляет поля в "employee" после вставки в "order"
CREATE TRIGGER trg_update_employee_info_from_order
AFTER INSERT ON orders
FOR EACH ROW EXECUTE FUNCTION update_employee_info_from_order();

-- Создание функции для установки close_date при закрытии вакансии
CREATE OR REPLACE FUNCTION set_close_date()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'closed' THEN
        NEW.close_date := CURRENT_DATE;
    ELSIF NEW.status = 'open' THEN
        RAISE EXCEPTION 'Cannot set close_date when vacancy status is open';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Создание триггера для автоматической установки close_date при изменении статуса вакансии
CREATE TRIGGER trg_set_close_date
BEFORE UPDATE ON vacancy
FOR EACH ROW
EXECUTE FUNCTION set_close_date();

-- Создание функции перед вставкой в таблицу orders
CREATE OR REPLACE FUNCTION before_insert_orders_trigger()
RETURNS TRIGGER AS $$
BEGIN
    -- Получение текущих значений current_job, current_salary и current_department для данного сотрудника
    SELECT current_job, current_salary, current_department
    INTO NEW.previous_job, NEW.previous_salary, NEW.previous_department
    FROM employee
    WHERE employee_id = NEW.employee_id;
    
    -- Возвращаем NEW, чтобы продолжить вставку записи в таблицу orders
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Создание триггера для вызова функции перед вставкой в таблицу orders
CREATE TRIGGER before_insert_orders_trigger
BEFORE INSERT ON orders
FOR EACH ROW EXECUTE FUNCTION before_insert_orders_trigger();