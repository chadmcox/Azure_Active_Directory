# KQL Basics

* tabular expression statement, which means both its input and output consist of tables or tabular datasets. Tabular statements contain zero or more operators
* each of which starts with a tabular input and returns a tabular output. Operators are sequenced by a | (pipe).
* Data flows, or is piped, from one operator to the next.
* It's like a funnel, where you start out with an entire data table. Each time the data passes through another operator, it is filtered, rearranged, or summarized.
* Because the piping of information from one operator to another is sequential, the query operator order is important and can affect both results and performance. At the end of the funnel, you're left with a refined output.

To retrieve data from a table you can simply run the name of the table:
```
SigninLogs 

```
This is a basic structure 
```
SigninLogs 
| where UserPrincipalName == "bob@contoso.com"
| project UserPrincipalName, AppDisplayName, CreatedDateTime

```

* KQL is extremely case sensitive.  the syntax of the command and the values being searched for are case sennsitive.

## Filtering

* Always start with a time filter
```

```
