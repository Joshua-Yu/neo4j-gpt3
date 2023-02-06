
// 
// Try some questions over the KG, by asking GPT-3 of course

// 
// 4. NLP steps: Entity & Relationship extraction
// 

// 1) api
:param openai_api_url=>'https://api.openai.com/v1/completions';
:param openai_api_header_content_type=>"application/json";
:param openai_api_header_auth=>"Bearer " + '***OpenAI-API-Key***';

// 2) model
:param openai_model=>"text-davinci-003";
:param openai_model_temperature=>0;
:param openai_model_max_tokens=>800;
:param openai_model_top_p=>0.5;
:param openai_model_frequency_penalty=>0;
:param openai_model_presence_penalty=>0.5;

// 3) prompt

//   Entity-Relationship extract
:param openai_prompt_er_extract_start=>'Extract entities and relationships from the following text:\n\n';
:param openai_prompt_er_extract_result_header=>'| entity | type | relationship | entity | type |';
//   Entity extract
:param openai_prompt_e_extract_start=>'Extract entities  from the following text:\n\n';
:param openai_prompt_e_extract_result_header=>'| entity | type |';
:param openai_prompt_result_skip=>'---';
:param openai_prompt_text=>'Cypher is the query language of neo4j graph database. ';
:param open_prompt_result_delimiter=>'|';

// 4.1 OpenAI API test
//    - APOC load.jsonParams
// Failed to invoke procedure `apoc.load.jsonParams`: Caused by: java.lang.NoSuchMethodError: 'com.fasterxml.jackson.core.util.JacksonFeatureSet com.fasterxml.jackson.core.JsonParser.getReadCapabilities()'
// Upgraded to 4.4.15 to have it solved.

// 4.1.1 Test read

WITH apoc.convert.toJson(
    {
        model: $openai_model,
        prompt: $openai_prompt_start + $openai_prompt_text + '\n\n' + $openai_prompt_result_header,
        temperature: $openai_model_temperature,
        max_tokens:  $openai_model_max_tokens,
        top_p:       $openai_model_top_p,
        frequency_penalty: $openai_model_frequency_penalty,
        presence_penalty : $openai_model_presence_penalty
    }) AS payload
CALL apoc.load.jsonParams(
    $openai_api_url,
    {
        `Content-Type`:'application/json',
        Authorization: $openai_api_header_auth
    },
    payload, null,
    {method:'POST'}
) YIELD value
WITH split(trim(value.choices[0].text), '\n') AS lines
UNWIND lines AS line
WITH split(line, $open_prompt_result_delimiter) AS tokens
WITH [tk IN tokens WHERE size(trim(tk)) > 0 AND NOT trim(tk) CONTAINS $openai_prompt_result_skip | trim(tk)] AS tok
WHERE size(tok) > 0
RETURN tok[0] AS ent1, tok[1] AS ent1type, tok[2] AS rel, tok[3] AS ent2, tok[4] AS ent2type;

// 4.1.2 Run with writes

// Run Entity-Relationship extraction for all Summary texts by openai API
// 
:auto MATCH (s:Summary) 
WITH s, 
     apoc.convert.toJson(
        {
            model: $openai_model,
            prompt: $openai_prompt_er_extract_start + s.text + '\n\n' + $openai_prompt_er_extract_result_header,
            temperature: $openai_model_temperature,
            max_tokens:  $openai_model_max_tokens,
            top_p:       $openai_model_top_p,
            frequency_penalty: $openai_model_frequency_penalty,
            presence_penalty : $openai_model_presence_penalty
        }) AS payload 
// LIMIT 1 
CALL {     
    WITH s, payload  
    CALL apoc.load.jsonParams(
        $openai_api_url,
        {
            `Content-Type`:'application/json',
            Authorization: $openai_api_header_auth
        },
        payload
    ) YIELD value
    WITH s, split(trim(value.choices[0].text), '\n') AS lines
    UNWIND lines AS line
    WITH s, split(line, $open_prompt_result_delimiter) AS tokens
    WITH s, [tk IN tokens WHERE size(trim(tk)) > 0 AND NOT trim(tk) CONTAINS $openai_prompt_result_skip | trim(tk)] AS tok
    WHERE size(tok) > 0
    // ----- 
    // Create and link entity through relationships extracted
    //   - new Entity nodes
    WITH s, tok[0] AS ent1, tok[1] AS ent1type, tok[2] AS rel, tok[3] AS ent2, tok[4] AS ent2type
    WHERE NOT (ent1 IS NULL OR ent2 IS NULL)  
    MERGE (e1:Entity{value:toLower(ent1)}) 
        ON CREATE SET e1.text = ent1, e1.type = ent1type
    MERGE (e2:Entity{value:toLower(ent2)}) 
        ON CREATE SET e2.text = ent2, e2.type = ent2type
    MERGE (s) -[:MENTIONS]-> (e1)
    MERGE (s) -[:MENTIONS]-> (e2) 
    //   - new Relationship
    WITH e1, e2, rel
    CALL apoc.cypher.doIt("MATCH (e1) WHERE id(e1) = $e1id 
                        MATCH (e2) WHERE id(e2) = $e2id 
                        MERGE (e1) -[:`" + toLower(rel) + "`]-> (e2)", 
                        {e1id:id(e1), e2id:id(e2)}
    ) YIELD value
    RETURN value
} IN TRANSACTIONS OF 100 ROWS
RETURN value IS NULL AS status;

// =========================================================
// Run Entity extraction for all Title texts by openai API
// 
:auto MATCH (s:Title) 
WITH s, 
     apoc.convert.toJson(
        {
            model: $openai_model,
            prompt: $openai_prompt_e_extract_start + s.text + '\n\n' + $openai_prompt_e_extract_result_header,
            temperature: $openai_model_temperature,
            max_tokens:  $openai_model_max_tokens,
            top_p:       $openai_model_top_p,
            frequency_penalty: $openai_model_frequency_penalty,
            presence_penalty : $openai_model_presence_penalty
        }) AS payload 
// LIMIT 1 
CALL {     
    WITH s, payload  
    CALL apoc.load.jsonParams(
        $openai_api_url,
        {
            `Content-Type`:'application/json',
            Authorization: $openai_api_header_auth
        },
        payload
    ) YIELD value
    WITH s, split(trim(value.choices[0].text), '\n') AS lines
    UNWIND lines AS line
    WITH s, split(line, $open_prompt_result_delimiter) AS tokens
    WITH s, [tk IN tokens WHERE size(trim(tk)) > 0 AND NOT trim(tk) CONTAINS $openai_prompt_result_skip | trim(tk)] AS tok
    WHERE size(tok) > 0
    // ----- 
    // Create and link entity through relationships extracted
    //   - new Entity nodes
    WITH s, tok[0] AS ent1, tok[1] AS ent1type
    WHERE NOT (ent1 IS NULL)  
    MERGE (e1:Entity{value:toLower(ent1)}) 
        ON CREATE SET e1.text = ent1, e1.type = ent1type
    MERGE (s) -[:MENTIONS]-> (e1)

} IN TRANSACTIONS OF 100 ROWS;

