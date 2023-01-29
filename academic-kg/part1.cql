
//
// 1. Schema 

:param arxiv_endpoint=>'https://export.arxiv.org/api/query?';
:param search_query=>'search_query=' + 'all:' + 'graph%20machine%20learning';
:param start_index=>'start=' + toString(0);
:param max_results=>'max_results=' + toString(50);

// schema

CREATE CONSTRAINT FOR (p:Paper) REQUIRE (p.id) IS UNIQUE;
CREATE CONSTRAINT FOR (a:Author) REQUIRE (a.fullname) IS UNIQUE;
CREATE CONSTRAINT FOR (y:Year) REQUIRE (y.year_number) IS UNIQUE;
CREATE CONSTRAINT FOR (e:Entity) REQUIRE (e.value) IS UNIQUE;

//
// 2. Retrieve metadata from search results 
//   - APOC load.xml
//   - Cypher: comprehension syntax
// 


CALL apoc.load.xml($arxiv_endpoint + $search_query + '&' + $start_index + '&' + $max_results) YIELD value
WITH value._children AS children
UNWIND children AS child
WITH child._children AS entry
WHERE child._type = 'entry'
WITH [attr IN entry WHERE attr._type IN ['id','title','summary','published'] | [attr._type,attr._text]] AS pairs,
     [attr IN entry WHERE attr._type = 'author' |  attr._children[0]._text] AS authors
RETURN apoc.map.fromPairs(pairs) AS article, authors;

// 
// 3. Create graph from the search results
//
//  3.1 The graph model part 1 

CALL apoc.load.xml($arxiv_endpoint + $search_query + '&' + $start_index + '&' + $max_results) YIELD value
WITH value._children AS children
UNWIND children AS child
WITH child._children AS entry
WHERE child._type = 'entry'
WITH [attr IN entry WHERE attr._type IN ['id','title','summary','published'] | [attr._type,attr._text]] AS pairs,
     [attr IN entry WHERE attr._type = 'author' |  attr._children[0]._text] AS authors
WITH apoc.map.fromPairs(pairs) AS article, authors
MERGE (p:Paper{id:article.id})
// Only create new nodes and relationships for new Paper
FOREACH (ignoreme IN CASE WHEN p.publish_date IS NULL THEN [1] ELSE {} END |
    CREATE (t:Title{text:article.title})
    CREATE (s:Summary{text:article.summary})
    MERGE (y:Year{year_number:left(coalesce(article.published,'yyyy'),4)})
    CREATE (p) -[:HAS_TITLE]-> (t)
    CREATE (p) -[:HAS_SUMMARY]-> (s)
    CREATE (p) -[:PUBLISHED_IN_YEAR]-> (y) 
) 
SET p.publish_date = left(coalesce(article.published,'yyyy-mm-dd'),10)
WITH article, authors, p, range(0,size(authors)-1) AS indx
UNWIND indx AS ind
MERGE (a:Author{fullname:authors[ind]})
MERGE (p) -[:HAS_AUTHOR{sequence:ind+1}]-> (a);


// 
// Link years 

MATCH (n:Year) 
WITH n 
ORDER by n.year_number ASC 
WITH collect(n) AS years, range(0,size(collect(n))-2) AS iterator
UNWIND iterator AS i
WITH years[i] AS y1, years[i+1] AS y2
MERGE (y1) -[:HAS_NEXT_YEAR]-> (y2);


// =======================================================================
//
// OpenAI GPT-3 prompt

//
// a) Generate prompt for nodes

CALL apoc.meta.data() YIELD label, property, type, elementType
WITH label, property, type, elementType
WHERE elementType <> 'relationship' AND type <> "RELATIONSHIP" 
WITH label, collect(property) AS props
RETURN '# ' + label + '(' + replace(
                                        reduce(propstr = '', p IN props | propstr + p + ',') + ')', 
                                        ',)',
                                        ')'
                                    ) AS line;

//
// b) Generate prompt for relationships

CALL apoc.meta.data() YIELD label, property, type, other, elementType
WITH label, property, type, other, elementType
WHERE elementType <> 'relationship' AND type = "RELATIONSHIP" 
WITH label, property, other
UNWIND other AS label2
RETURN '# (:' + label + ') -[:' + property + ']-> (:' + label2 + ')' AS line; 

// c) Generate prompt for Uniqueness Constraints

SHOW UNIQUE CONSTRAINT YIELD *
WHERE entityType = 'NODE'
RETURN 'CREATE CONSTRAINT FOR (n:`' 
       + labelsOrTypes[0] + '`) REQUIRE (' 
       + replace(reduce(propstr = '', p IN properties | propstr + 'n.`' + p + '`,') + ')' + ' IS UNIQUE;', ',)', ')')
AS statement;


// 
// Test OpenAI Codex for Cypher code generation 
//

### Neo4j Cypher labels and relationships, with their properties:
#
# Paper(id,publish_date)
# Author(fullname)
# Year(year_number)
# Title(text)
# Summary(text)
# (:Paper) -[:HAS_TITLE]-> (:Title)
# (:Paper) -[:PUBLISHED_IN_YEAR]-> (:Year)
# (:Paper) -[:HAS_AUTHOR]-> (:Author)
# (:Paper) -[:HAS_SUMMARY]-> (:Summary)
# (:Year) -[:HAS_NEXT_YEAR]-> (:Year)
# CREATE CONSTRAINT FOR (p:Paper) REQUIRE (p.id) IS UNIQUE;
# CREATE CONSTRAINT FOR (a:Author) REQUIRE (a.fullname) IS UNIQUE;
# CREATE CONSTRAINT FOR (y:Year) REQUIRE (y.year_number) IS UNIQUE;
### A query to find the author of a paper 'abc'
MATCH (p:Paper {id: 'abc'}) -[:HAS_AUTHOR]-> (a:Author) RETURN a.fullname


// ### samples

### A query to find authors who have co-authored the most number of papers
MATCH
  (a:Author)-[:HAS_AUTHOR]->(p:Paper)<-[:HAS_AUTHOR]-(b:Author)
WHERE
  a <> b
RETURN
  a.fullname,
  b.fullname,
  count(p) AS num_papers
ORDER BY
  num_papers DESC
LIMIT
  10

### A query to find the authors of a paper 'abc', and what other papers they have published
MATCH (p:Paper {id:'abc'})-[:HAS_AUTHOR]->(a:Author)<-[:HAS_AUTHOR]-(other_p:Paper)
RETURN a.fullname, other_p.id, other_p.publish_date

### A query to find the authors who have published most number of papers
MATCH (a:Author)-[:HAS_AUTHOR]->(p:Paper)
RETURN a.fullname, COUNT(p)
ORDER BY COUNT(p) DESC
LIMIT 10


