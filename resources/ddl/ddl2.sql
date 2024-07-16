/*
 */

drop view cf_data;

DROP TABLE public.prompt_templates;

CREATE TABLE public.prompt_templates (
	id serial NOT NULL,
	"template" varchar NULL
);

/* 1. Prepare tables */
CREATE OR REPLACE FUNCTION prepare_tables()
RETURNS void
AS
$$
begin
	drop table if exists syn_data_01;
	drop table if exists syn_data_02;
	drop table if exists syn_data_03;
	drop table if exists syn_data_04;
	drop table if exists syn_data_05;
	drop table if exists syn_data_06;

	create table syn_data_01 (
		id int4 NULL,
		chunk json NULL
	);

	CREATE TABLE syn_data_02 (
		id int4 NULL,
		chunk_index text NULL,
		chunk text NULL,
		question_generator_input text NULL,
		answer_generator_input text NULL
	);

	CREATE TABLE public.syn_data_03 (
		id int4 NULL,
		chunk text NULL,
		chunk_index text NULL,
		answer_generator_input text NULL,
		output_raw text NULL
	);

	CREATE TABLE public.syn_data_04 (
		id int4 NULL,
		chunk_index text NULL,
		chunk text NULL,
		answer_generator_input text NULL,
		question text NULL
	);

	CREATE TABLE public.syn_data_05 (
		id int4 NULL,
		chunk_index text NULL,
		chunk text NULL,
		answer_generator_input text NULL,
		question text NULL,
		answer text NULL
	);

	CREATE TABLE public.syn_data_06 (
		id int4 NULL,
		chunk_index text NULL,
		chunk text NULL,
		answer_generator_input text NULL,
		question text NULL,
		answer text null,
		embedding vector null
	);

END;
$$
LANGUAGE plpgsql;


/* 2. Generate chunks */
CREATE OR REPLACE FUNCTION generate_chunks(curr_id int)
RETURNS void
AS
$$
begin
	insert into syn_data_01
	select id,
		row_to_json(pgml.chunk('recursive_character', context)) as chunk
		from cloudfoundry
		where id = curr_id;
END;
$$
LANGUAGE plpgsql;

/* 3. Generate question prompts */
CREATE OR REPLACE FUNCTION generate_question_prompts()
RETURNS void
AS
$$
begin
	insert into syn_data_02
	select syn_data_01.id,
		chunk::json->>'chunk_index' as chunk_index,
		chunk::json->>'chunk' as chunk,
		replace(pt.template, '__PROMPTINPUT__', chunk::json->>'chunk') as question_generator_input,
		replace(pt2.template , '__PROMPTINPUT__', chunk::json->>'chunk') as answer_generator_input
		from syn_data_01, prompt_templates pt, prompt_templates pt2
		where pt.template_type = 'default'
		and pt2.template_type ='question_answer'
		order by id, chunk_index;
END;
$$
LANGUAGE plpgsql;


/* 4. Generate question completions for the prompt inputs */
CREATE OR REPLACE FUNCTION generate_questions()
RETURNS void
AS
$$
begin
	insert into syn_data_03
	select id,
	chunk,
	chunk_index,
	answer_generator_input,
	pgml.transform(
		task   => '{"task": "text-generation","model": "microsoft/Phi-3-mini-4k-instruct","torch_dtype": "bfloat16","trust_remote_code": "True"}'::JSONB,
		args => '{"max_new_tokens": 500}'::JSONB,
		inputs => ARRAY[question_generator_input]
	)::jsonb -> 0 -> 0 ->> 'generated_text' as output_raw
	from syn_data_02;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION parse_questions_from_completions()
RETURNS void
AS
$$
begin
	insert into syn_data_04
	select id,
		chunk_index,
		chunk,
		answer_generator_input,
		substring(output_raw from '\w*copywriter\|\>.*' || num || '\.(.*)\n' || (num+1) || '\.') as question
		from generate_series(1, 6) as num, syn_data_03;
END;
$$
LANGUAGE plpgsql;

/* 6. Generate answer completions for the prompt inputs */
CREATE OR REPLACE FUNCTION generate_answers()
RETURNS void
AS
$$
begin
	insert into syn_data_05
	select id,
	chunk_index,
	chunk,
	answer_generator_input,
	question,
	pgml.transform(
		task   => '{"task": "text-generation","model": "microsoft/Phi-3-mini-4k-instruct","torch_dtype": "bfloat16","trust_remote_code": "True"}'::JSONB,
		args => '{"max_new_tokens": 500}'::JSONB,
		inputs => ARRAY[replace(answer_generator_input,'__PROMPTQUESTION__', question)]
	)::jsonb -> 0 -> 0 ->> 'generated_text' as answer
	from syn_data_04;
END;
$$
LANGUAGE plpgsql;


/* 7. Stage generated data */
CREATE OR REPLACE FUNCTION stage_synthetic_data()
RETURNS void
AS
$$
begin
	insert into syn_data_06
	select syn05.id,
		syn05.chunk_index,
		syn05.chunk,
		syn05.answer_generator_input,
		syn05.question,
		syn05.answer,
		pgml.embed('microsoft/Phi-3-mini-4k-instruct', answer)::vector as embedding
		from syn_data_05 syn05;
END;
$$
LANGUAGE plpgsql;


/* Driver function
 *
 */
CREATE OR REPLACE FUNCTION generate_synthetic_data()
RETURNS void
AS
$$
DECLARE ids CURSOR FOR SELECT id from cloudfoundry c2 ;
        curr_id int;
begin
	open ids;
	LOOP
        FETCH NEXT FROM ids INTO curr_id;
        EXIT WHEN NOT FOUND;
        /* 1. Prepare tables */
        perform prepare_tables();
		/* 2. Generate chunks */
		perform generate_chunks(curr_id);
		/* 3. Generate question prompts */
		perform generate_question_prompts();
		/* 4. Generate question completions for the prompt inputs */
		perform generate_questions();
		/* 5. Parse questions from completions */
		perform parse_questions_from_completions();
		/* 6. Generate answer completions for the prompt inputs */
		perform generate_answers();
		/* 7. Stage generated data */
		perform stage_synthetic_data();
	end loop;
	close ids;
END;
$$
LANGUAGE plpgsql;