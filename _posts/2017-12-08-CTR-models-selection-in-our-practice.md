---
layout: post
title: "关于Model和Model Ensembling在CTR中适用场景的理解"
description: ""
category: "Chinese"
tags: [geek]
---
{% include JB/setup %}

## LR

### LR 适合什么样的特征

作为一个广义线性模型，LR 数学模型简单，权重和输出可解释，容易并行化训练，容易改造 Online Learning。简直是工业界的宠儿。但正是因为他模型简单，对特征的要求就高一些。属于典型的复杂特征+简单模型的套路（1）。

那么，feed 给 LR 的特征，需要长成啥样呢？

首先，我们认为全局特征是可以的。但是他在全局特征上学出来的东西，往往对个体是有偏的。而为了同时兼顾个性化，我们通常需要利用大量的 ID 类特征。常见的 ID 类特征，比如 query ID，ad ID，ad provider ID,  url ID 等。实际上，任何分类（ categorical ）的特征，比如年龄、地域、星期几，我们都可以 discrete到 one-hot 的上面。然后用简单模型 LR 来学习和记住（memorize）这些信息。LR 对于这些信息的权重是记录在weight 里面的。

只要这个特征出现过，LR 通常都能够给到这个特征一个尽量合理的权重，通过正则化（regularzation），还可以舍弃那些不是很 strong 的特征信号，让模型的泛化能力更好一些。

### 为什么要做特征交叉组合

在工业实践中，对于离散特征我们通常要用特征组合的方式产生新的交叉特征，那么为什么这样做呢？

举一个例子。假设我们现在有两维特征，一个是性别（男 ，女），另一个是年龄（-10, 10-18,18-35, 35-60, 60+）。如果不做特征交叉，经过 LR 的学习，我们可以拿到的是男性对于广告的整体点击概率（男这个特征的权重），女对于广告的整体点击概率（女这个特征的权重），以及各个年龄段对于这个广告的点击权重。那么好了，如果是一个爆款女高跟鞋。那么可以想见，女性作为一个整体，肯定对这个广告的点击率是比较高的（因为年轻女性是网购主力啊），那么模型会倾向于只要是女性来了（女性特征命中），就好给出一个比较置信的结论，这个广告就会排上来。但是，这显然对于一个60岁以上的女性老人是不适用的。换句话说，全局的特征（女），平均化了部分用户（女老人），使得他们没法得到一个更好的预测。

如果我们做了特征交叉，就会得到类似这样的 cross features：Female_and_10-18，Female_and_18-35，Female_and_60+，这样，大量的年轻女性的点击高跟鞋的样本，就会落到Female_and_10-18，Female_and_18-35这俩特征上，他们会不断被强化。反而单独Female和Female_and_60+特征权重就会下降。这样，我们再来一个Female_and_60+的用户，就不大可能推荐高跟鞋给老太太了。

### 统计类特征和LR特征weight的关系
其实对于ID 类或离散类特征的处理，我们有两种在我看来是等效的方式：
* 一种是通过离线统计的方式，做一些 statistic 的特征出来（比如过去一个月的平均点击率等等），在统计过程中，注意一下置信度这种东西就好了。比如一个广告过去一个月只展现了3次，然后被用户点了1次，你就不能说这玩意的历史点击率是33%，因为样本太少了不置信。要考虑置信区间来做处理。
* 依靠 LR 的方式，把 ID 类的经验信息学到特征的 weight 上来。通过 FTRL 或者 BOPR 的方式，可以让线上的模型实时的去更新这些 weight（他们的 loss 函数，把分布的置信区间啥的考虑进去了）。

那么哪种好呢？其实各有优劣。第一种不免引入很多 离线的log 统计啊啥的，通常会引入大几分钟级别的时延。如果系统设计得好，比如我早年在腾讯广点通团队实现的 CloudX 系列，通过流式系统来收集日志merge 特征，通过 kv 系统来保存特征，可以做到十几秒级别的特征更新，但也基本到头了。第二种对于在线的 server 开发能力要求较高，因为一个广告展现了，你总要有一个 session 窗口来等待，如果有人点，那么 merge 成一个正样本，如果没人点，那么过了窗口等待时间后就形成一个负样本。

在我们搜索推荐的场景下，目前还是采用的第一种。因为第二种对于负样本的判断太草率了，我们要考虑 skip 等等情况，离线进行的计算比较多。

## GBDT和NN

### 关于 Boosting 思想

GBDT以及后来深受工业界和竞赛届宠爱的 XGBoost，都是一类Boosted Tree 模型。关于Boosting理论，简直是一个非常简单，细想想又无懈可击，非常强大的理论。实际思想是说，比如对于一个分类任务，如果我们能够有一个较弱的分类器，可以进行准确率大于50%的预测，那么这个任务就可以被拆解成一个已经完成的任务，和一个更小的任务（弱分类器做不好的那部分）。然后在这个更小的任务上，我们又可以找到另一个弱分类器，来进行一个大于50%的预测。这个过程可以一直 repeat 下去，直到原始的大问题被我们 N 个弱分类器联合解决掉。

可以注意到，这些弱分类器并不一定都是决策树（像 GBDT 那样），而可以是任何还有点用的模型。只不过在实践中，我们发现决策树是天然很适合这种 Boosting 场景的。那么，其他模型 Boosting 或者 Ensembling 的效果如何呢？

### 各种 Ensembing 的优劣

微软 Bing Search Ads 团队去年发表的一篇论文(2)，将当今工业界常用的 LR、GBDT 和 NN 模型各种 Ensemble， 做了很多有意思的尝试。 里面也提到了 Facebook 关于 GBDT to LR 的尝试（3）。里面有很多有意思的见解和我们团队的实践是基本契合的。最后他们发现，NN+GBDT 的方式是最牛的。其实我个人觉得，可以更大胆一点去尝试多层蛋糕式的 Boosting，充分发挥 N种模型的优势。不过因为工程上的重重限制，我们还需要慢慢探索。

### 参考资料

1. 在广告LR模型中，为什么要做特征组合？ - 严林的回答 - 知乎 https://www.zhihu.com/question/34271604/answer/58357055
2. 微软 Bing Search Ads 关于模型 Ensembling的论文：https://www.microsoft.com/en-us/research/wp-content/uploads/2017/04/main-1.pdf
3. Facebook 关于 GBDT to LR 的尝试：http://quinonero.net/Publications/predicting-clicks-facebook.pdf