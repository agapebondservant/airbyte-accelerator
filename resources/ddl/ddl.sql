DROP TABLE public.prompt_templates;

CREATE TABLE public.prompt_templates (
	id serial NOT NULL,
	"template" varchar NULL
);

drop view cf_data;

-- drop view cf_data;

create view cf_data as
/* 1. Generate chunks */
with chunks as (
	select id,
	row_to_json(pgml.chunk('recursive_character', context)) as chunk
	from cloudfoundry
),
/* 2. Generate question prompts */
question_prompts as (
	select pt.template default_tpl,
	pt2."template" question_answer_tpl
	from prompt_templates pt , prompt_templates pt2
	where pt.template_type = 'default'
	and pt2.template_type ='question_answer'
),
/* 3. Generate inputs for the question prompts */
question_prompt_inputs as (
	select id,
	chunk::json->>'chunk_index' as chunk_index,
	chunk::json->>'chunk' as chunk,
	replace(default_tpl, '__PROMPTINPUT__', chunk::json->>'chunk') as question_generator_input,
	replace(question_answer_tpl , '__PROMPTINPUT__', chunk::json->>'chunk') as answer_generator_input
	from chunks, question_prompts
	order by id, chunk_index
),
/* 4. Generate question completions for the prompt inputs */
question_prompt_completions as (
	select id,
	chunk_index,
	answer_generator_input,
	pgml.transform(
		task   => '{"task": "text-generation","model": "microsoft/Phi-3-mini-4k-instruct","torch_dtype": "bfloat16","trust_remote_code": "True"}'::JSONB,
		args => '{"max_new_tokens": 500}'::JSONB,
		inputs => ARRAY[question_generator_input]
	)::jsonb -> 0 -> 0 ->> 'generated_text' as output_raw
	from question_prompt_inputs
),
/* 5. Parse questions from completions */
questions as (
	select id,
	chunk_index,
	answer_generator_input,
	substring(output_raw from '\w*copywriter\|\>.*\\n' || num || '\.(.*)\\n' || (num+1)) as question
	from generate_series(1, 6) as num, question_prompt_completions
),
/* 6. Generate answer completions for the prompt inputs */
answers as (
	select id,
	chunk_index,
	pgml.transform(
		task   => '{"task": "text-generation","model": "microsoft/Phi-3-mini-4k-instruct","torch_dtype": "bfloat16","trust_remote_code": "True"}'::JSONB,
		args => '{"max_new_tokens": 500}'::JSONB,
		inputs => ARRAY[replace(answer_generator_input,'__PROMPTQUESTION__', question)]
	)::jsonb -> 0 -> 0 ->> 'generated_text' as answer
	from questions
)


select question_prompt_inputs.id,
question_prompt_inputs.chunk_index,
question_prompt_inputs.chunk,
question_generator_input,
output_raw ,
question,
answer
from question_prompt_inputs, question_prompt_completions, questions, answers
where question_prompt_inputs.id = question_prompt_completions.id
and question_prompt_inputs.chunk_index = question_prompt_completions.chunk_index
and question_prompt_inputs.id = questions.id
and question_prompt_inputs.chunk_index = questions.chunk_index
and question_prompt_inputs.id = answers.id
and question_prompt_inputs.chunk_index = answers.chunk_index;
