# Survey capture 

* The survey support architecture is very simple. 
* For each question, there are 2 types: `text` and `mcq`
* For `text` we use a `TextField`, for `mcq` we use a `DropDownButton`
* Each question in `sites.json` has a `questionId`, and this is used to track responses in a Map
* When the user hits submit, these fields are transferred to a `CapturedSession` object and written to a file 
