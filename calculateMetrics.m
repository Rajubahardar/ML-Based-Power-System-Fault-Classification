
function [accuracy,macroF1,CM,classMetrics] = ...
    calculateMetrics(actual,predicted,classNames)

actual = string(actual(:));
predicted = string(predicted(:));
classNames = string(classNames(:));

nClasses = numel(classNames);
CM = zeros(nClasses,nClasses);

for i = 1:nClasses
    for j = 1:nClasses
        CM(i,j) = sum( ...
            actual == classNames(i) & ...
            predicted == classNames(j));
    end
end

total = sum(CM,'all');

if total == 0
    accuracy = NaN;
    macroF1 = NaN;
    classMetrics = table();
    return;
end

accuracy = sum(diag(CM))/total;

precision = zeros(nClasses,1);
recall = zeros(nClasses,1);
f1 = zeros(nClasses,1);

for i = 1:nClasses
    TP = CM(i,i);
    FP = sum(CM(:,i))-TP;
    FN = sum(CM(i,:))-TP;

    if TP+FP > 0
        precision(i) = TP/(TP+FP);
    end

    if TP+FN > 0
        recall(i) = TP/(TP+FN);
    end

    if precision(i)+recall(i) > 0
        f1(i) = 2*precision(i)*recall(i)/ ...
            (precision(i)+recall(i));
    end
end

macroF1 = mean(f1);

classMetrics = table( ...
    classNames,precision,recall,f1, ...
    'VariableNames',{'Class','Precision','Recall','F1'});

end
