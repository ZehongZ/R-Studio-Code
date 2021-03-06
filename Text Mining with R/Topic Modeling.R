#Topic modeling is a method of unsupervised classification of such documents, silimar to clustering on numeric data, which finds natural groups of items
#Laten Dirichlet allocation (LDA).Every document is a mixture of topics; Every topic is a mixture of words
library(topicmodels)
data("AssociatedPress")
AssociatedPress
head(AssociatedPress)

#Set a seed so that the output of the model is predictable
ap_lda<-LDA(AssociatedPress,k=2,control = list(seed=1234))
ap_lda

#Word-Topic Probabilities
library(tidytext)
ap_topics<-tidy(ap_lda, matrix="beta")
ap_topics

#Find the 10 terms that are most common within each topic
library(ggplot2)
library(dplyr)

ap_top_terms<-ap_topics%>%
  group_by(topic)%>%
  top_n(10,beta)%>%
  ungroup()%>%
  arrange(topic, -beta)
ap_top_terms%>%
  mutate(term=reorder(term,beta))%>%
  ggplot(aes(term, beta, fill=factor(topic)))+
  geom_col(show.legend = FALSE)+
  facet_wrap(~topic, scales = "free")+
  coord_flip()

#The words with the greatest differences between the two topics
library(tidyr)
beta_spread<-ap_topics%>%
  mutate(topic=paste0("topic",topic))%>%
  spread(topic, beta)%>%
  filter(topic1>.001 | topic2>.001)%>%
  mutate(log_ratio = log2(topic2/topic1))
beta_spread

#Document-Topic PRobabilities
ap_documents<-tidy(ap_lda, matrix="gamma")
ap_documents

tidy(AssociatedPress)%>%
  filter(document==6)%>%
  arrange(desc(count))

#Using topic modeling to discover how chapters cluster into distinct topics
titles<-c("Twenty Thousand Leagues under the Sea", "The War of the Worlds","Pride and Prejudice","Great Expectations")
library(gutenbergr)          
books<-gutenberg_works(title %in% titles)%>%
  gutenberg_download(meta_fields = "title")

library(stringr)
#Divide into documents, each representing one chapter
reg<-regex("^chapter", ignore_case=TRUE)
by_chapter<-books%>%
  group_by(title)%>%
  mutate(chapter=cumsum(str_detect(text,reg)))%>%
  ungroup()%>%
  filter(chapter>0)%>%
  unite(document, title, chapter)
#Split into words
by_chapter_word<-by_chapter%>%
  unnest_tokens(word, text)
#Find document-word counts
word_counts<-by_chapter_word%>%
  anti_join(stop_words)%>%
  count(document, word, sort=TRUE)%>%
  ungroup()
word_counts

#LDA on Chapters
#Cast a one-token-per-row table into a DocumentTermMatrix 
chapters_dtm<-word_counts%>%
  cast_dtm(document, word, n)
chapters_dtm
#Using LDA() function to create a four-topic model
chapters_lda<-LDA(chapters_dtm, k=4, control=list(seed=1234))
chapters_lda
#Examine per-topic-per-word probabilities
chapter_topics<-tidy(chapters_lda, matrix="beta")
chapter_topics
#Find top five terms within each topic
top_terms<-chapter_topics%>%
  group_by(topic)%>%
  top_n(5,beta)%>%
  ungroup()%>%
  arrange(topic, -beta)
top_terms
#Visualization
library(ggplot2)
top_terms%>%
  mutate(term=reorder(term, beta))%>%
  ggplot(aes(term, beta, fill=factor(topic)))+
  geom_col(show.legend = FALSE)+
  facet_wrap(~topic, scales="free")+
  coord_flip()

#Per-Document Classification
chapters_gamma<-tidy(chapters_lda, matrix="gamma")
chapters_gamma
chapters_gamma<-chapters_gamma%>%
  separate(document,c("title","chapter"), sep="_",convert = TRUE)
chapters_gamma
#Reorder titiles in order of topic 1, topic 2 before plotting
chapters_gamma%>%
  mutate(title=reorder(title,gamma*topic))%>%
  ggplot(aes(factor(topic),gamma))+
  geom_boxplot()+
  facet_wrap(~title)

chapter_classifications<-chapters_gamma%>%
  group_by(title, chapter)%>%
  top_n(1,gamma)%>%
  ungroup()
chapter_classifications
#Compare each to the "consensus" topic for each book and see which were most often misidentified
book_topics<-chapter_classifications%>%
  count(title, topic)%>%
  group_by(title)%>%
  top_n(1,n)%>%
  ungroup()%>%
  transmute(consensus=title, topic)
chapter_classifications%>%
  inner_join(book_topics,by="topic")%>%
  filter(title!=consensus)

#By-Word Assignments:augment
assignments<-augment(chapters_lda, data=chapters_dtm)
assignments
#Combine this assignments table with the consensus book titles to find which words were incorrectly classified
assignments<-assignments%>%
  separate(document, c("title","chapter"), sep="_",convert = TRUE)%>%
  inner_join(book_topics, by=c(".topic"="topic"))
assignments
library(scales)
assignments%>%
  count(title, consensus, wt=count)%>%
  group_by(title)%>%
  mutate(percent=n/sum(n))%>%
  ggplot(aes(consensus, title, fill=percent))+
  geom_tile()+
  scale_fill_gradient2(high="red",label=percent_format())+
  theme_minimal()+
  theme(axis.text.x=element_text(angle=90,hjust=1),panel.grid = element_blank())+
  labs(x="Book words were assigned to",
       y="Book words came from",
       fill="% of assignments")
#Most commonly mistaken words
wrong_words<-assignments%>%
  filter(title!=consensus)
wrong_words%>%
  count(title, consensus, term, wt=count)%>%
  ungroup()%>%
  arrange(desc(n))
#Wrongly classified words that never appeared in the novel they were misassigned
word_counts%>%
  filter(word=="flopson")

#Alternative LDA Implementations
library(rJava)
library(mallet)
#Create a vector with one string per chapter
collapsed<-by_chapter_word%>%
  anti_join(stop_words, by="word")%>%
  mutate(word=str_replace(word, "'",""))%>%
  group_by(document)%>%
  summarize(text=paste(word, collapse = " "))
#Create an empty file of "stop words"
file.create(empty_file<-tempfile())
docs<-mallet.import(collapsed$document,collapsed$text, empty_file)
mallet_model<-MalletLDA(num.topics=4)
mallet_model$loadDocuments(docs)
mallet_model$train(100)
#Word-topic pairs
tidy(mallet_model)
#Document-topic pairs
tidy(mallet_model, matrix="gamma")
#Column needs to be named "term" for "augment"
term_counts<-rname(word_counts, term=word)
augment(mallet_model, term_counts)