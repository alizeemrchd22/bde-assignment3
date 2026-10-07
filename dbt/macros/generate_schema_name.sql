-- By default dbt adds the target schema in front of custom schemas
-- (e.g. "dbt_assignment3_silver"). I want clean names that match the
-- medallion layers, so I use the custom schema name as it is.
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
